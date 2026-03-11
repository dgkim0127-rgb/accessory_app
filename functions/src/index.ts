// functions/src/index.ts
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

/* ───────────────────── 공통 유틸 ───────────────────── */
function normalizeRole(role: unknown): "user" | "admin" | "super" {
  const v = String(role ?? "user").toLowerCase();
  if (v === "admin" || v === "super") return v;
  return "user";
}

function toHttpsError(error: any): HttpsError {
  const code = String(error?.code ?? "");
  const message = String(error?.message ?? "서버 내부 오류가 발생했습니다.");

  if (
    code === "auth/email-already-exists" ||
    code === "auth/uid-already-exists"
  ) {
    return new HttpsError("already-exists", "이미 존재하는 계정입니다.");
  }

  if (
    code === "auth/invalid-password" ||
    code === "auth/invalid-email" ||
    code === "auth/missing-email" ||
    code === "auth/missing-password"
  ) {
    return new HttpsError("invalid-argument", message);
  }

  if (code === "auth/user-not-found") {
    return new HttpsError("not-found", "사용자를 찾을 수 없습니다.");
  }

  if (code === "auth/insufficient-permission") {
    return new HttpsError("permission-denied", "권한이 없습니다.");
  }

  return new HttpsError("internal", message);
}

async function assertSuper(req: any) {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  const doc = await db.collection("users").doc(uid).get();
  const role = String(doc.exists ? (doc.data() as any)?.role ?? "guest" : "guest");

  if (role !== "super") {
    throw new HttpsError("permission-denied", "최종 관리자만 사용할 수 있습니다.");
  }

  return uid;
}

async function assertAdminOrSuper(req: any) {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  const doc = await db.collection("users").doc(uid).get();
  const role = String(doc.exists ? (doc.data() as any)?.role ?? "guest" : "guest");

  if (role !== "admin" && role !== "super") {
    throw new HttpsError("permission-denied", "관리자 전용 기능입니다.");
  }

  return { uid, role };
}

/* ───────────────────── Super 계정 관리 ───────────────────── */
export const superCreateUser = onCall({ region: "asia-northeast3" }, async (req) => {
  const caller = await assertSuper(req);
  const { email, password, role } = req.data || {};

  if (typeof email !== "string" || !email.trim()) {
    throw new HttpsError("invalid-argument", "email 이 필요합니다.");
  }
  if (typeof password !== "string" || password.length < 6) {
    throw new HttpsError("invalid-argument", "password 는 6자 이상이어야 합니다.");
  }

  const normalizedEmail = email.trim().toLowerCase();
  const normalizedRole = normalizeRole(role);

  try {
    const created = await getAuth().createUser({
      email: normalizedEmail,
      password,
      emailVerified: false,
    });

    await getAuth().setCustomUserClaims(created.uid, { role: normalizedRole });

    await db.collection("users").doc(created.uid).set({
      email: normalizedEmail,
      role: normalizedRole,
      createdBy: caller,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      uid: created.uid,
      email: normalizedEmail,
      role: normalizedRole,
    };
  } catch (error: any) {
    console.error("[superCreateUser]", error);
    throw toHttpsError(error);
  }
});

export const superDeleteUser = onCall({ region: "asia-northeast3" }, async (req) => {
  await assertSuper(req);
  const { uid } = req.data || {};

  if (typeof uid !== "string" || !uid.trim()) {
    throw new HttpsError("invalid-argument", "uid가 필요합니다.");
  }

  const targetUid = uid.trim();

  try {
    await getAuth().deleteUser(targetUid).catch((e: any) => {
      if (e?.code !== "auth/user-not-found") throw e;
    });

    await db.collection("users").doc(targetUid).delete().catch(() => {});
    return { ok: true };
  } catch (error: any) {
    console.error("[superDeleteUser]", error);
    throw toHttpsError(error);
  }
});

export const superSetRole = onCall({ region: "asia-northeast3" }, async (req) => {
  await assertSuper(req);
  const { uid, role } = req.data || {};

  if (typeof uid !== "string" || !uid.trim()) {
    throw new HttpsError("invalid-argument", "uid가 필요합니다.");
  }

  const normalizedRole = normalizeRole(role);
  const targetUid = uid.trim();

  try {
    await db.collection("users").doc(targetUid).set(
      { role: normalizedRole },
      { merge: true }
    );

    const user = await getAuth().getUser(targetUid);
    await getAuth().setCustomUserClaims(targetUid, {
      ...(user.customClaims || {}),
      role: normalizedRole,
    });

    return { ok: true, uid: targetUid, role: normalizedRole };
  } catch (error: any) {
    console.error("[superSetRole]", error);
    throw toHttpsError(error);
  }
});

/* ───────── 역할 변경 시 Custom Claims 동기화 ───────── */
export const syncUserRoleClaim = onDocumentUpdated(
  { document: "users/{uid}", region: "asia-northeast3" },
  async (event) => {
    const uid = event.params.uid;
    const after = event.data?.after?.data() as any;
    if (!after) return;

    const role = normalizeRole(after.role);

    try {
      const auth = getAuth();
      const user = await auth.getUser(uid);
      const oldRole = (user.customClaims || {}).role;

      if (oldRole === role) return;

      await auth.setCustomUserClaims(uid, {
        ...(user.customClaims || {}),
        role,
      });

      console.log(`[claims] ${uid} -> ${role}`);
    } catch (error) {
      console.error("[syncUserRoleClaim]", error);
    }
  }
);

/* ───────── 테스트 푸시 ───────── */
export const sendTestPushToUser = onCall({ region: "asia-northeast3" }, async (req) => {
  const { uid, title, body } = req.data || {};
  if (typeof uid !== "string" || !uid.trim()) {
    throw new HttpsError("invalid-argument", "uid가 필요합니다.");
  }

  try {
    const snap = await db.collection("users").doc(uid.trim()).get();
    const token = snap.get("fcmToken") as string | undefined;

    if (!token) {
      throw new HttpsError("failed-precondition", "이 사용자는 fcmToken이 없습니다.");
    }

    await getMessaging().send({
      token,
      notification: {
        title: title || "알림 테스트",
        body: body || "푸시가 잘 오면 성공!",
      },
      android: { priority: "high" },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { sound: "default" } },
      },
    });

    console.log(`[push] 테스트 알림 전송 - uid=${uid}`);
    return { ok: true };
  } catch (error: any) {
    if (error instanceof HttpsError) throw error;
    console.error("[sendTestPushToUser]", error);
    throw toHttpsError(error);
  }
});

/* ───────── 전체 공지 ───────── */
export const broadcastAll = onCall({ region: "asia-northeast3" }, async (req) => {
  await assertSuper(req);

  const { title, body, data } = req.data || {};

  try {
    const tokens: string[] = [];
    const snap = await db.collection("users").select("fcmToken").get();

    snap.forEach((d) => {
      const t = d.get("fcmToken");
      if (t && typeof t === "string") tokens.push(t);
    });

    if (tokens.length === 0) {
      throw new HttpsError("failed-precondition", "보낼 fcmToken이 없습니다.");
    }

    const base: Omit<MulticastMessage, "tokens"> = {
      notification: {
        title: title || "전체 공지",
        body: body || "새 소식이 도착했어요.",
      },
      data: { type: "broadcast", ...(data || {}) },
    };

    const chunkSize = 500;
    let success = 0;
    let failure = 0;

    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const res = await getMessaging().sendEachForMulticast({
        ...base,
        tokens: chunk,
      });
      success += res.successCount;
      failure += res.failureCount;
    }

    console.log(`[broadcastAll] total=${tokens.length} success=${success} failure=${failure}`);
    return { total: tokens.length, success, failure };
  } catch (error: any) {
    if (error instanceof HttpsError) throw error;
    console.error("[broadcastAll]", error);
    throw toHttpsError(error);
  }
});

/* ───────── 게시물 기반 brands.postsCount 자동 집계 ───────── */
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
  const { uid: caller } = await assertAdminOrSuper(req);
  const { brandId } = req.data || {};

  if (typeof brandId !== "string" || !brandId.trim()) {
    throw new HttpsError("invalid-argument", "brandId 가 필요합니다.");
  }

  const normalizedBrandId = brandId.trim();
  const brandRef = db.collection("brands").doc(normalizedBrandId);

  try {
    const agg = await db
      .collection("posts")
      .where("brandId", "==", normalizedBrandId)
      .count()
      .get();

    const realCount = (agg.data().count ?? 0) as number;

    if (realCount > 0) {
      throw new HttpsError("failed-precondition", "게시물이 있어 삭제할 수 없습니다.");
    }

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(brandRef);
      if (!snap.exists) return;

      const again = await db
        .collection("posts")
        .where("brandId", "==", normalizedBrandId)
        .count()
        .get();

      const c2 = (again.data().count ?? 0) as number;

      if (c2 > 0) {
        throw new HttpsError("failed-precondition", "삭제 직전에 게시물이 생겼습니다.");
      }

      tx.delete(brandRef);
    });

    console.log(`[deleteBrandIfEmpty] brandId=${normalizedBrandId} deleted by uid=${caller}`);
    return { ok: true, message: "브랜드가 삭제되었습니다." };
  } catch (error: any) {
    if (error instanceof HttpsError) throw error;
    console.error("[deleteBrandIfEmpty]", error);
    throw toHttpsError(error);
  }
});