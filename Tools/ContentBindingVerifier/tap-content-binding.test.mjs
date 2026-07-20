import assert from "node:assert/strict";
import test from "node:test";
import {
  TAP_PROOF_SLOT,
  encodeProofSlotPayload,
  readProofEnvelopeData,
  sha256Base64URL,
  sha256Base64URLExcludingProofSlot,
  writeProofEnvelope,
} from "./tap-content-binding.mjs";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

test("BMFF proof slot is excluded from asset hash", async () => {
  const baseData = concatBytes(
    bmffBox("ftyp", textEncoder.encode("heic")),
    bmffBox("meta", Uint8Array.from([0, 0, 0, 0, 0x69, 0x69, 0x64, 0])),
    bmffBox("mdat", textEncoder.encode("primary-image-bytes-and-depth-aux-bytes")),
  );
  const emptySlotData = concatBytes(baseData, bmffProofBox());
  const proofSlotData = writeProofEnvelope(
    emptySlotData,
    "heic",
    textEncoder.encode("proof-envelope"),
  );

  assert.equal(
    await sha256Base64URLExcludingProofSlot(emptySlotData, "heic"),
    await sha256Base64URL(baseData),
  );
  assert.equal(
    await sha256Base64URLExcludingProofSlot(proofSlotData, "heic"),
    await sha256Base64URL(baseData),
  );
  assert.equal(
    textDecoder.decode(readProofEnvelopeData(proofSlotData, "heic")),
    "proof-envelope",
  );
});

test("JPEG APP11 proof slot is excluded from asset hash", async () => {
  const baseData = Uint8Array.from([
    0xff, 0xd8,
    0xff, 0xe0, 0x00, 0x04, 0x4a, 0x46,
    0xff, 0xd9,
  ]);
  const emptySlotData = jpegWithProofSlot(baseData);
  const proofSlotData = writeProofEnvelope(
    emptySlotData,
    "jpeg",
    textEncoder.encode("proof-envelope"),
  );

  assert.equal(
    await sha256Base64URLExcludingProofSlot(emptySlotData, "jpeg"),
    await sha256Base64URL(baseData),
  );
  assert.equal(
    await sha256Base64URLExcludingProofSlot(proofSlotData, "jpeg"),
    await sha256Base64URL(baseData),
  );
  assert.equal(
    textDecoder.decode(readProofEnvelopeData(proofSlotData, "jpeg")),
    "proof-envelope",
  );
});

test("proof slot parser rejects non-zero padding after envelope", () => {
  const baseData = concatBytes(
    bmffBox("ftyp", textEncoder.encode("heic")),
    bmffBox("mdat", textEncoder.encode("asset bytes")),
  );
  const proofSlotData = writeProofEnvelope(
    concatBytes(baseData, bmffProofBox()),
    "heic",
    textEncoder.encode("proof-envelope"),
  );
  proofSlotData[proofSlotData.length - 1] = 0x01;

  assert.throws(
    () => readProofEnvelopeData(proofSlotData, "heic"),
    /padding is not zero-filled/u,
  );
});

test("proof slot parser rejects duplicate slots", () => {
  const baseData = concatBytes(
    bmffBox("ftyp", textEncoder.encode("heic")),
    bmffBox("mdat", textEncoder.encode("asset bytes")),
  );
  const firstSlot = bmffProofBox();
  const duplicateSlotData = concatBytes(baseData, firstSlot, firstSlot);

  assert.throws(
    () => readProofEnvelopeData(duplicateSlotData, "heic"),
    /expected exactly one TAP proof slot; found 2/u,
  );
});

function bmffProofBox() {
  const payload = encodeProofSlotPayload();
  const box = new Uint8Array(8 + TAP_PROOF_SLOT.bmffUUID.length + payload.length);
  writeUInt32BE(box, 0, box.length);
  box.set(textEncoder.encode("uuid"), 4);
  box.set(TAP_PROOF_SLOT.bmffUUID, 8);
  box.set(payload, 8 + TAP_PROOF_SLOT.bmffUUID.length);
  return box;
}

function bmffBox(type, payload) {
  const box = new Uint8Array(8 + payload.length);
  writeUInt32BE(box, 0, box.length);
  box.set(textEncoder.encode(type), 4);
  box.set(payload, 8);
  return box;
}

function jpegWithProofSlot(baseData) {
  const payload = encodeProofSlotPayload();
  const segment = new Uint8Array(2 + 2 + payload.length);
  segment[0] = 0xff;
  segment[1] = 0xeb;
  writeUInt16BE(segment, 2, payload.length + 2);
  segment.set(payload, 4);
  return concatBytes(baseData.subarray(0, 2), segment, baseData.subarray(2));
}

function concatBytes(...chunks) {
  const length = chunks.reduce((total, chunk) => total + chunk.length, 0);
  const output = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}

function writeUInt16BE(bytes, offset, value) {
  bytes[offset] = (value >>> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

function writeUInt32BE(bytes, offset, value) {
  bytes[offset] = (value >>> 24) & 0xff;
  bytes[offset + 1] = (value >>> 16) & 0xff;
  bytes[offset + 2] = (value >>> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}
