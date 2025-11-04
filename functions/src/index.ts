// functions/src/index.ts  ✅ 최종 (클라이언트 증감 제거 대응)
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging, MulticastMessage } from "firebase-admin/messaging";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";

initializeApp();
const db = getFirestore();

/* ───────────────────── 공통 권한 함수 ───────────────────── */
async function assertSuper(context: any) {
  const uid = context.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const doc = await db.collection("users").doc(uid).get();
  const role = (doc.exists ? (doc.data() as any).role : "guest") || "guest";
  if (role !== "super") {
    throw new HttpsError("permission-denied", "최종 관리자만 사용할 수 있습니다.");
  }
  return uid;
}

/* ───────────────────── Super 계정 관리 ───────────────────── */
export const superCreateUser = onCall({ region: "asia-northeast3" }, async (req) => {
  const caller = await assertSuper(req);
  const { email, password, role } = req.data || {};
  if (typeof email !== "string" || typeof password !== "string") {
    throw new HttpsError("invalid-argument", "email, password가 필요합니다.");
  }
  const normalizedRole = role === "admin" ? "admin" : "user";
  const created = await getAuth().createUser({ email, password, emailVerified: false });
  await getAuth().setCustomUserClaims(created.uid, { role: normalizedRole });
  await db.collection("users").doc(created.uid).set({
    email,
    role: normalizedRole,
    createdBy: caller,
    createdAt: new Date(),
  });
  return { uid: created.uid };
});

export const superDeleteUser = onCall({ region: "asia-northeast3" }, async (req) => {
  await assertSuper(req);
  const { uid } = req.data || {};
  if (typeof uid !== "string" || !uid)
    throw new HttpsError("invalid-argument", "uid가 필요합니다.");
  await getAuth()
    .deleteUser(uid)
    .catch((e: any) => {
      if (e?.code !== "auth/user-not-found") throw e;
    });
  await db.collection("users").doc(uid).delete().catch(() => {});
  return { ok: true };
});

export const superSetRole = onCall({ region: "asia-northeast3" }, async (req) => {
  await assertSuper(req);
  const { uid, role } = req.data || {};
  if (typeof uid !== "string" || !uid)
    throw new HttpsError("invalid-argument", "uid가 필요합니다.");
  const allowed = ["user", "admin", "super"];
  if (!allowed.includes(role))
    throw new HttpsError("invalid-argument", "role은 user/admin/super 중 하나여야 합니다.");
  await db.collection("users").doc(uid).update({ role });
  await getAuth().setCustomUserClaims(uid, { role });
  return { ok: true };
});

/* ───────── 역할 변경 시 Custom Claims 동기화 ───────── */
export const syncUserRoleClaim = onDocumentUpdated(
  { document: "users/{uid}", region: "asia-northeast3" },
  async (event) => {
    const uid = event.params.uid;
    const after = event.data?.after?.data() as any;
    if (!after) return;

    const roleRaw = String(after.role ?? "user").toLowerCase();
    const role = roleRaw === "admin" || roleRaw === "super" ? roleRaw : "user";

    const auth = getAuth();
    const user = await auth.getUser(uid);
    const oldRole = (user.customClaims || {}).role;
    if (oldRole === role) return;

    await auth.setCustomUserClaims(uid, { ...(user.customClaims || {}), role });
    console.log(`[claims] ${uid} -> ${role}`);
  }
);

/* ───────── 테스트 푸시 ───────── */
export const sendTestPushToUser = onCall({ region: "asia-northeast3" }, async (req) => {
  const { uid, title, body } = req.data || {};
  if (!uid) throw new HttpsError("invalid-argument", "uid가 필요합니다.");

  const snap = await db.collection("users").doc(uid).get();
  const token = snap.get("fcmToken") as string | undefined;
  if (!token)
    throw new HttpsError("failed-precondition", "이 사용자는 fcmToken이 없습니다.");

  await getMessaging().send({
    token,
    notification: { title: title || "알림 테스트", body: body || "푸시가 잘 오면 성공!" },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
  });
  console.log(`[push] 테스트 알림 전송 - uid=${uid}`);
  return { ok: true };
});

/* ───────── 전체 공지 ───────── */
export const broadcastAll = onCall({ region: "asia-northeast3" }, async (req) => {
  const caller = req.auth?.uid;
  if (!caller) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const callerDoc = await db.collection("users").doc(caller).get();
  const callerRole = (callerDoc.data() as any)?.role || "user";
  if (callerRole !== "super")
    throw new HttpsError("permission-denied", "최종 관리자만 발송할 수 있습니다.");

  const { title, body, data } = req.data || {};
  const tokens: string[] = [];
  const snap = await db.collection("users").select("fcmToken").get();
  snap.forEach((d) => {
    const t = d.get("fcmToken");
    if (t && typeof t === "string") tokens.push(t);
  });
  if (tokens.length === 0)
    throw new HttpsError("failed-precondition", "보낼 fcmToken이 없습니다.");

  const base: Omit<MulticastMessage, "tokens"> = {
    notification: {
      title: title || "전체 공지",
      body: body || "새 소식이 도착했어요.",
    },
    data: { type: "broadcast", ...(data || {}) },
  };

  const chunkSize = 500;
  let success = 0,
    failure = 0;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    const res = await getMessaging().sendEachForMulticast({ ...base, tokens: chunk });
    success += res.successCount;
    failure += res.failureCount;
  }
  console.log(`[broadcastAll] total=${tokens.length} success=${success} failure=${failure}`);
  return { total: tokens.length, success, failure };
});

/* ───────── 게시물 기반 brands.postsCount 자동 집계 ───────── */

// 게시물 생성 시 +1
export const onPostCreatedIncBrandCount = onDocumentCreated(
  { document: "posts/{postId}", region: "asia-northeast3" },
  async (event) => {
    const data = event.data?.data() as any | undefined;
    const brandId = data?.brandId;
    if (!brandId) return;
    await db
      .collection("brands")
      .doc(brandId)
      .set({ postsCount: FieldValue.increment(1) }, { merge: true });
  }
);

// 게시물 삭제 시 -1
export const onPostDeletedDecBrandCount = onDocumentDeleted(
  { document: "posts/{postId}", region: "asia-northeast3" },
  async (event) => {
    const data = event.data?.data() as any | undefined;
    const brandId = data?.brandId;
    if (!brandId) return;
    await db
      .collection("brands")
      .doc(brandId)
      .update({ postsCount: FieldValue.increment(-1) })
      .catch(() => {});
  }
);

// 게시물 brandId 변경 시 이전 브랜드 -1, 새 브랜드 +1
export const onPostUpdatedAdjustBrandCount = onDocumentUpdated(
  { document: "posts/{postId}", region: "asia-northeast3" },
  async (event) => {
    const before = event.data?.before?.data() as any;
    const after = event.data?.after?.data() as any;
    const beforeBrand = before?.brandId;
    const afterBrand = after?.brandId;
    if (!beforeBrand || !afterBrand || beforeBrand === afterBrand) return;

    await db.collection("brands").doc(beforeBrand)
      .update({ postsCount: FieldValue.increment(-1) })
      .catch(() => {});
    await db.collection("brands").doc(afterBrand)
      .set({ postsCount: FieldValue.increment(1) }, { merge: true });
  }
);

/* ───────── 게시물 없는 브랜드만 삭제 ───────── */
export const deleteBrandIfEmpty = onCall({ region: "asia-northeast3" }, async (req) => {
  const caller = req.auth?.uid;
  if (!caller) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  const userDoc = await db.collection("users").doc(caller).get();
  const role = (userDoc.data() as any)?.role || "user";
  if (role !== "admin" && role !== "super")
    throw new HttpsError("permission-denied", "관리자 전용 기능입니다.");

  const { brandId } = req.data || {};
  if (typeof brandId !== "string" || !brandId)
    throw new HttpsError("invalid-argument", "brandId 가 필요합니다.");

  const brandRef = db.collection("brands").doc(brandId);
  const agg = await db.collection("posts").where("brandId", "==", brandId).count().get();
  const realCount = (agg.data().count ?? 0) as number;

  if (realCount > 0)
    throw new HttpsError("failed-precondition", "게시물이 있어 삭제할 수 없습니다.");

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(brandRef);
    if (!snap.exists) return;
    const again = await db.collection("posts").where("brandId", "==", brandId).count().get();
    const c2 = (again.data().count ?? 0) as number;
    if (c2 > 0)
      throw new HttpsError("failed-precondition", "삭제 직전에 게시물이 생겼습니다.");
    tx.delete(brandRef);
  });

  console.log(`[deleteBrandIfEmpty] brandId=${brandId} deleted by uid=${caller}`);
  return { ok: true, message: "브랜드가 삭제되었습니다." };
});
