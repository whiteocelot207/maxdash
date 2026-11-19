#!/usr/bin/env node
// Verifier referensi untuk protokol Link A + parser tautan Google Maps.
// Menjalankan SEMUA vektor dari maxdash dan memastikan algoritma benar sebelum
// kode Swift dibangun / dipakai di motor. Jalankan: node app/tools/verify_vectors.mjs
//
// Sumber vektor: app/Tests/Resources/vectors (salinan dari toolkit maxdash).
// Implementasi ini harus identik dengan Swift (CRC32/MPEG-2, frame, sesi, share-link).
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const VEC = join(here, "..", "Tests");
const readVec = (name) => JSON.parse(readFileSync(join(VEC, name), "utf8"));

// ---------- util heks ----------
const parseHex = (s) => {
  const clean = (s || "").replace(/[^0-9a-fA-F]/g, "");
  const out = Buffer.alloc(Math.floor(clean.length / 2));
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
  return out;
};
const toHex = (buf) => Buffer.from(buf).toString("hex").toUpperCase().match(/.{1,2}/g)?.join(" ") ?? "";

// ---------- CRC-32/MPEG-2 ----------
function crc32Mpeg2(buf, crc = 0xffffffff) {
  for (const byte of buf) {
    crc ^= byte << 24;
    for (let i = 0; i < 8; i++) {
      crc = crc & 0x80000000 ? ((crc << 1) ^ 0x04c11db7) >>> 0 : (crc << 1) >>> 0;
    }
  }
  return crc >>> 0;
}
const crcHex = (buf) => "0x" + crc32Mpeg2(buf).toString(16).toUpperCase().padStart(8, "0");

// ---------- encode/decode frame ----------
const MAGIC = Buffer.from([0x6e, 0x41, 0x6c, 0x40]); // nAl@
const VERSION = 0x01;

function encodeFrame({ direction, command, flag, payload }) {
  const head = Buffer.alloc(12);
  MAGIC.copy(head, 0);
  head[4] = VERSION;
  head[5] = direction & 0xff;
  head[6] = command & 0xff;
  head.writeUInt32LE(payload.length, 7);
  head[11] = flag & 0xff;
  const body = Buffer.concat([head, payload]);
  const crc = crc32Mpeg2(body);
  const out = Buffer.alloc(16 + payload.length);
  head.copy(out, 0);
  out.writeUInt32LE(crc, 12);
  payload.copy(out, 16);
  return out;
}

function decodeFrame(buf) {
  if (buf.length < 16) throw new Error("frame too short");
  if (!buf.subarray(0, 4).equals(MAGIC)) throw new Error("bad magic");
  const version = buf[4];
  const direction = buf[5];
  const command = buf[6];
  const length = buf.readUInt32LE(7);
  const flag = buf[11];
  const crc = buf.readUInt32LE(12);
  const payload = buf.subarray(16, 16 + length);
  const calc = crc32Mpeg2(Buffer.concat([buf.subarray(0, 12), payload]));
  const crcOk = (calc >>> 0) === (crc >>> 0);
  return { version, direction, command, length, flag, payload, crc, crcOk };
}

// ---------- interpretasi "means" per command (bike -> phone) ----------
function screenForPart(part) {
  if (part === "006-B3952-01") return [480, 234];
  if (part.includes("006-B4160")) return [480, 240];
  return [480, 234];
}
function interpret(command, payload) {
  switch (command) {
    case 66:
      return { serial: payload.toString("ascii") };
    case 82:
      return { authenticated: payload[0] === 1 };
    case 83: {
      const part = Buffer.from(payload.subarray(0, 12).map((b) => b ^ 0x0a)).toString("ascii");
      const key = Buffer.from(payload.subarray(12, 16).map((b) => b ^ 0x0a));
      return { part_number: part, key_hex: toHex(key), screen: screenForPart(part) };
    }
    case 55:
      return { start_frames: payload.length === 2 && payload[0] === 1 && payload[1] === 0 };
    case 56:
      return { pause: true };
    case 65: {
      const speed = payload.length >= 3 ? payload.readUInt16LE(1) : 0;
      return { speed_kmh: speed };
    }
    case 51:
      return { button: "up" };
    case 52:
      return { button: "down" };
    case 80:
      return { ack_frame_id: payload.length >= 2 ? payload.readUInt16LE(0) : 0 };
    default:
      return {};
  }
}

// ---------- parser tautan (Google/Apple Maps) ----------
function decodeSeg(s) {
  try {
    return decodeURIComponent(s.replace(/\+/g, " "));
  } catch {
    return s;
  }
}
function parseLatLng(s) {
  if (!s) return null;
  const m = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(s);
  if (!m) return null;
  return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
}
const inRange = (p) => p && p.lat >= -90 && p.lat <= 90 && p.lng >= -180 && p.lng <= 180;

function parseShare(text) {
  const urlMatch = /https?:\/\/[^\s]+/.exec(text || "");
  if (!urlMatch) return { kind: "none" };
  let url;
  try {
    url = new URL(urlMatch[0]);
  } catch {
    return { kind: "none" };
  }
  const host = url.hostname.toLowerCase();
  const isGoogle = host.includes("google") || host === "goo.gl" || host.endsWith(".goo.gl");
  const isApple = host.includes("apple");
  const isShort = host === "maps.app.goo.gl" || (host === "goo.gl" && url.pathname.startsWith("/maps"));
  if (!isGoogle && !isApple) return { kind: "none" };
  if (isShort) return { kind: "redirect", url: urlMatch[0] };

  const path = url.pathname;
  const params = url.searchParams;

  // 1) directions
  if (/\/maps\/dir\//.test(path)) {
    const segs = path.split("/").filter(Boolean);
    const di = segs.indexOf("dir");
    const tail = segs.slice(di + 1);
    const wpSegs = [];
    for (const s of tail) {
      if (s.startsWith("@") || s.startsWith("data=") || s.includes("data=")) break;
      wpSegs.push(s);
    }
    const names = wpSegs.map((s) => {
      const raw = decodeSeg(s);
      return parseLatLng(raw) ? null : raw;
    });
    const coords = [];
    const re = /!1d(-?\d+(?:\.\d+)?)!2d(-?\d+(?:\.\d+)?)/g;
    let m;
    while ((m = re.exec(urlMatch[0])) !== null) coords.push({ lng: parseFloat(m[1]), lat: parseFloat(m[2]) });
    const wps = wpSegs.map((s, i) => {
      const raw = parseLatLng(decodeSeg(s));
      const c = raw ? { lat: raw.lat, lng: raw.lng } : coords[i] || null;
      return { name: names[i], coords: c };
    });
    if (wps.length === 0) return { kind: "none" };
    const dest = wps[wps.length - 1];
    let destination;
    if (dest.coords && inRange(dest.coords)) {
      destination = { lat: dest.coords.lat, lng: dest.coords.lng };
      if (dest.name) destination.name = dest.name;
    } else {
      destination = { q: dest.name };
    }
    if (destination.q === undefined && destination.lat === undefined) return { kind: "none" };
    if (destination.lat !== undefined && !inRange(destination)) return { kind: "none" };
    const stops = [];
    for (let i = 1; i < wps.length - 1; i++) {
      const w = wps[i];
      if (w.coords && inRange(w.coords)) stops.push({ ...w.coords, ...(w.name ? { name: w.name } : {}) });
    }
    return { kind: "directions", destination, stops };
  }

  // 2) place
  if (/\/maps\/place\//.test(path)) {
    const segs = path.split("/").filter(Boolean);
    const pi = segs.indexOf("place");
    const nameSeg = segs[pi + 1] || "";
    const name = decodeSeg(nameSeg);
    const m = /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/.exec(urlMatch[0]);
    if (m) {
      const lat = parseFloat(m[1]);
      const lng = parseFloat(m[2]);
      if (!inRange({ lat, lng })) return { kind: "none" };
      return { kind: "coords", lat, lng, ...(name ? { name } : {}) };
    }
    return { kind: "query", q: name };
  }

  // 3) search (maps urls api)
  if (/\/maps\/search\//.test(path) || params.get("api") === "1") {
    const q = params.get("query") ?? params.get("q");
    if (q) {
      const c = parseLatLng(q);
      if (c) return inRange(c) ? { kind: "coords", ...c } : { kind: "none" };
      return { kind: "query", q };
    }
  }

  // 4) apple maps ll + q
  if (isApple) {
    const ll = params.get("ll");
    const c = ll ? parseLatLng(ll) : null;
    if (c && inRange(c)) {
      const q = params.get("q");
      return { kind: "coords", ...c, ...(q ? { name: q } : {}) };
    }
  }

  // 5) query params q / ll / query / destination
  for (const key of ["q", "ll", "query", "destination"]) {
    const val = params.get(key);
    if (!val) continue;
    const c = parseLatLng(val);
    if (c) return inRange(c) ? { kind: "coords", ...c } : { kind: "none" };
    if (key === "q" || key === "query" || key === "destination") return { kind: "query", q: val };
  }

  // 6) @lat,lng,zoom viewport
  const at = /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:,|-?\d)/.exec(urlMatch[0]);
  if (at) {
    const lat = parseFloat(at[1]);
    const lng = parseFloat(at[2]);
    if (!inRange({ lat, lng })) return { kind: "none" };
    return { kind: "coords", lat, lng };
  }

  return { kind: "none" };
}

// ---------- mesin sesi (handshake) ----------
class Session {
  constructor(send) {
    this.send = send;
    this.seen83 = false;
    this.initSent = false;
    this.roadText = " ";
    this.speedLimit = 0;
    this.started = false;
  }
  emit(command, flag, payload) {
    this.send({ command, flag, payload });
  }
  onBikeFrame(frame) {
    const { command, flag, payload } = frame;
    switch (command) {
      case 66:
        this.emit(81, 0, Buffer.from([0x01, 0x00]));
        this.emit(33, 1, Buffer.from([0x7c, 0x06, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]));
        break;
      case 82:
        if (this.seen83 && !this.initSent) {
          this.sendInit();
          this.initSent = true;
        }
        break;
      case 83: {
        this.seen83 = true;
        this.initSent = false;
        const key = Buffer.from(payload.subarray(12, 16).map((b) => b ^ 0x0a));
        this.emit(84, 1, key);
        break;
      }
      case 55:
        if (payload[0] === 1 && payload[1] === 0) {
          this.emit(2, 0, Buffer.from([0x00, 0x00]));
          this.emit(14, 1, Buffer.from([0x07, 0x1a, 0x00, 0x00]));
          this.emit(13, 0, Buffer.from([0x01, 0x00]));
          this.emit(3, 1, Buffer.from(this.roadText, "utf8"));
          this.emit(10, 0, Buffer.from([0x00, 0x00]));
          this.emit(11, 0, Buffer.from([0x00, 0x00]));
          this.started = true;
        }
        break;
      case 51:
      case 52:
        this.emit(14, 1, Buffer.from([0x07, 0x1a, 0x00, 0x00]));
        break;
      default:
        break;
    }
  }
  sendInit() {
    this.emit(2, 0, Buffer.from([0x00, 0x00]));
    this.emit(31, 0, Buffer.from([0x01, 0x00]));
    this.emit(10, 0, Buffer.from([0x00, 0x00]));
    this.emit(14, 1, Buffer.from([0x07, 0x1a, 0x00, 0x00]));
    this.emit(11, 0, Buffer.from([0x00, 0x00]));
    this.emit(13, 0, Buffer.from([0x01, 0x00]));
    this.emit(3, 1, Buffer.from(this.roadText, "utf8"));
    const limit = Buffer.alloc(9);
    limit.writeFloatLE(this.speedLimit, 0);
    limit[4] = 4;
    Buffer.from("km/h", "ascii").copy(limit, 5);
    this.emit(17, 1, limit);
    this.emit(12, 0, Buffer.from([0x01, 0x00]));
  }
}

// ---------- runner ----------
let pass = 0;
let fail = 0;
const fails = [];
function check(id, ok, detail) {
  if (ok) {
    pass++;
  } else {
    fail++;
    fails.push(`${id}: ${detail}`);
  }
}
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const f32 = (a, b) => Math.abs(a - b) < 1e-6;

// CRC
for (const v of readVec("crc.json").vectors) {
  const got = crcHex(parseHex(v.input.hex));
  check(`crc:${v.id}`, got === v.expect.crc32_mpeg2, `got ${got} want ${v.expect.crc32_mpeg2}`);
}
// frames
for (const v of readVec("frames.json").vectors) {
  const frame = encodeFrame({
    direction: v.input.direction,
    command: v.input.command,
    flag: v.input.flag,
    payload: parseHex(v.input.payload_hex),
  });
  check(`frame:${v.id}`, toHex(frame) === v.expect.frame_hex, `got ${toHex(frame)}`);
}
// commands (decode + means)
for (const v of readVec("link-a-commands.json").vectors) {
  try {
    const f = decodeFrame(parseHex(v.input.frame_hex));
    const means = interpret(f.command, f.payload);
    const exp = v.expect;
    let ok = f.crcOk && f.command === exp.command && f.flag === exp.flag && toHex(f.payload) === exp.payload_hex;
    if (ok && exp.means) {
      for (const [k, val] of Object.entries(exp.means)) {
        const got = means[k];
        const match = Array.isArray(val) ? eq(got, val) : got === val;
        if (!match) {
          ok = false;
          check(`cmd:${v.id}`, false, `means.${k} got ${JSON.stringify(got)} want ${JSON.stringify(val)}`);
        }
      }
    }
    check(`cmd:${v.id}`, ok, ok ? "" : "command/flag/payload mismatch");
  } catch (e) {
    check(`cmd:${v.id}`, false, String(e));
  }
}
// handshake
{
  const vec = readVec("handshake-nmax-turbo.json").vectors[0];
  const out = [];
  const session = new Session((f) => out.push({ command: f.command, flag: f.flag, payload_hex: toHex(f.payload) }));
  for (const step of vec.input.steps) {
    if (step.from === "bike") {
      session.onBikeFrame(decodeFrame(parseHex(step.frame_hex)));
    } else if (step.must_send) {
      const got = out.splice(0, out.length);
      const want = step.must_send.map((s) => ({ command: s.command, flag: s.flag, payload_hex: s.payload_hex }));
      check(`handshake:${vec.id}:${step.must_send[0].command}`, eq(got, want), `got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
    }
  }
}
// share links
for (const v of readVec("share-links.json").vectors) {
  const got = parseShare(v.input.text);
  const exp = v.expect;
  let ok = got.kind === exp.kind;
  let why = ok ? "" : `kind got ${got.kind} want ${exp.kind}`;
  if (ok && exp.kind === "coords") {
    ok = f32(got.lat, exp.lat) && f32(got.lng, exp.lng) && (exp.name === undefined || got.name === exp.name);
    why = ok ? "" : `coords got ${JSON.stringify(got)}`;
  } else if (ok && exp.kind === "query") {
    ok = got.q === exp.q;
    why = ok ? "" : `q got ${JSON.stringify(got.q)} want ${exp.q}`;
  } else if (ok && exp.kind === "directions") {
    const d = got.destination || {};
    if (exp.destination.q !== undefined) ok = d.q === exp.destination.q;
    else ok = f32(d.lat, exp.destination.lat) && f32(d.lng, exp.destination.lng) && (exp.destination.name === undefined || d.name === exp.destination.name);
    ok = ok && Array.isArray(got.stops) && got.stops.length === exp.stops.length;
    if (ok) {
      for (let i = 0; i < exp.stops.length; i++) {
        const gs = got.stops[i];
        const es = exp.stops[i];
        if (!f32(gs.lat, es.lat) || !f32(gs.lng, es.lng) || (es.name !== undefined && gs.name !== es.name)) ok = false;
      }
    }
    why = ok ? "" : `directions got ${JSON.stringify(got)}`;
  }
  check(`share:${v.id}`, ok, why);
}

console.log(`\n${pass} lulus, ${fail} gagal`);
if (fail) {
  console.log("\nGAGAL:");
  for (const f of fails) console.log("  - " + f);
  process.exit(1);
} else {
  console.log("Semua vektor LULUS. Algoritma Link A & parser tautan benar.");
}