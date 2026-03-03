// tools/update_remote_config.js ✅ 최종(Windows 안정화 버전)
// - GOOGLE_APPLICATION_CREDENTIALS에 지정된 서비스계정 JSON을 직접 읽어서
//   credential + projectId를 확실히 세팅한 뒤 Remote Config 갱신

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

function readBuildNumber() {
  const pubspecPath = path.join(process.cwd(), "pubspec.yaml");
  const txt = fs.readFileSync(pubspecPath, "utf8");
  const m = txt.match(/version:\s*([0-9.]+)\+([0-9]+)/);
  if (!m) throw new Error("pubspec.yaml에서 version: x.y.z+N 형식을 찾지 못했습니다.");
  return parseInt(m[2], 10);
}

function loadServiceAccount() {
  const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!p) {
    throw new Error("GOOGLE_APPLICATION_CREDENTIALS 환경변수가 비어 있습니다.");
  }
  if (!fs.existsSync(p)) {
    throw new Error(`서비스계정 파일이 없습니다: ${p}`);
  }
  const json = JSON.parse(fs.readFileSync(p, "utf8"));
  if (!json.project_id) {
    throw new Error("서비스계정 JSON에 project_id가 없습니다.");
  }
  return json;
}

async function main() {
  const sa = loadServiceAccount();
  const build = readBuildNumber();

  // ✅ projectId를 명시해서 Remote Config가 확실히 그 프로젝트로 호출되게 함
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: sa.project_id,
  });

  const rc = admin.remoteConfig();
  const template = await rc.getTemplate();

  function setParam(key, value) {
    template.parameters[key] = template.parameters[key] || {};
    template.parameters[key].defaultValue = { value: String(value) };
  }

  // ✅ A-1: 새 빌드 나오면 즉시 구버전 차단
  setParam("recommendedBuild", build);
  setParam("minBuild", build);
  setParam("forceUpdate", "true");
  // androidStoreUrl은 콘솔에서 1회 세팅 후 유지 추천(스크립트에서 건드리지 않음)

  await rc.validateTemplate(template);
  await rc.publishTemplate(template);

  console.log(
    `[OK] Remote Config updated: project=${sa.project_id} minBuild=${build}, recommendedBuild=${build}, forceUpdate=true`
  );
}

main().catch((e) => {
  console.error("[FAIL]", e);
  process.exit(1);
});