const textEncoder = new TextEncoder();

const MAGIC = textEncoder.encode("TAPCAM-PROOF-SLOT-V1");
const BMFF_UUID = Uint8Array.from([
  0x54, 0x41, 0x50, 0x43, 0x41, 0x4d, 0x50, 0x52,
  0x4f, 0x4f, 0x46, 0x53, 0x4c, 0x4f, 0x54, 0x31,
]);

export const TAP_PROOF_SLOT = Object.freeze({
  payloadByteCount: 60 * 1024,
  headerByteCount: 32,
  version: 1,
  magic: MAGIC,
  bmffUUID: BMFF_UUID,
});

export function locateProofSlot(input, container) {
  const bytes = asBytes(input);
  switch (container) {
    case "heic":
    case "bmff":
      return locateBMFFProofSlot(bytes);
    case "jpeg":
    case "jpg":
      return locateJPEGProofSlot(bytes);
    default:
      throw new Error(`unsupported proof slot container: ${container}`);
  }
}

export function readProofEnvelopeData(input, container) {
  const bytes = asBytes(input);
  const slot = locateProofSlot(bytes, container);
  const payload = bytes.slice(slot.payloadOffset, slot.payloadOffset + slot.payloadLength);

  if (
    payload.length !== TAP_PROOF_SLOT.payloadByteCount ||
    !sameBytes(payload.subarray(0, MAGIC.length), MAGIC) ||
    readUInt32BE(payload, 24) !== TAP_PROOF_SLOT.version
  ) {
    throw new Error("invalid proof slot header");
  }

  const envelopeLength = readUInt32BE(payload, 28);
  const capacity = TAP_PROOF_SLOT.payloadByteCount - TAP_PROOF_SLOT.headerByteCount;
  if (envelopeLength <= 0) {
    throw new Error("missing proof envelope");
  }
  if (envelopeLength > capacity) {
    throw new Error("invalid proof envelope length");
  }

  const envelopeStart = TAP_PROOF_SLOT.headerByteCount;
  const envelopeEnd = envelopeStart + envelopeLength;
  for (let offset = envelopeEnd; offset < payload.length; offset += 1) {
    if (payload[offset] !== 0) {
      throw new Error("proof slot padding is not zero-filled");
    }
  }

  return payload.slice(envelopeStart, envelopeEnd);
}

export function encodeProofSlotPayload(envelopeInput = new Uint8Array()) {
  const envelope = asBytes(envelopeInput);
  const capacity = TAP_PROOF_SLOT.payloadByteCount - TAP_PROOF_SLOT.headerByteCount;
  if (envelope.length > capacity) {
    throw new Error("proof envelope exceeds fixed proof slot");
  }

  const payload = new Uint8Array(TAP_PROOF_SLOT.payloadByteCount);
  payload.set(MAGIC, 0);
  writeUInt32BE(payload, 24, TAP_PROOF_SLOT.version);
  writeUInt32BE(payload, 28, envelope.length);
  payload.set(envelope, TAP_PROOF_SLOT.headerByteCount);
  return payload;
}

export function writeProofEnvelope(input, container, envelopeInput) {
  const bytes = asBytes(input);
  const slot = locateProofSlot(bytes, container);
  const output = new Uint8Array(bytes);
  output.set(encodeProofSlotPayload(envelopeInput), slot.payloadOffset);
  return output;
}

export async function sha256Base64URL(input) {
  const bytes = asBytes(input);

  if (globalThis.crypto?.subtle) {
    const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
    return base64URL(new Uint8Array(digest));
  }

  const { createHash } = await import("node:crypto");
  return createHash("sha256").update(bytes).digest("base64url");
}

export async function sha256Base64URLExcludingProofSlot(input, container) {
  const bytes = asBytes(input);
  const slot = locateProofSlot(bytes, container);
  return sha256Base64URL(concatBytes(
    bytes.subarray(0, slot.containerOffset),
    bytes.subarray(slot.containerOffset + slot.containerLength),
  ));
}

function locateBMFFProofSlot(bytes) {
  let offset = 0;
  const matches = [];

  while (offset + 8 <= bytes.length) {
    const boxStart = offset;
    const size32 = readUInt32BE(bytes, offset);
    const typeOffset = offset + 4;
    offset += 8;

    let boxSize;
    if (size32 === 1) {
      if (offset + 8 > bytes.length) {
        break;
      }
      const largeSize = readUInt64BE(bytes, offset);
      if (largeSize > BigInt(Number.MAX_SAFE_INTEGER)) {
        break;
      }
      boxSize = Number(largeSize);
      offset += 8;
    } else if (size32 === 0) {
      boxSize = bytes.length - boxStart;
    } else {
      boxSize = size32;
    }

    const boxEnd = boxStart + boxSize;
    if (boxSize < offset - boxStart || boxEnd > bytes.length) {
      break;
    }

    if (
      ascii(bytes, typeOffset, 4) === "uuid" &&
      offset + BMFF_UUID.length <= boxEnd &&
      sameBytes(bytes.subarray(offset, offset + BMFF_UUID.length), BMFF_UUID)
    ) {
      const payloadOffset = offset + BMFF_UUID.length;
      matches.push({
        kind: "bmff-uuid-proof-slot",
        containerOffset: boxStart,
        containerLength: boxSize,
        payloadOffset,
        payloadLength: boxEnd - payloadOffset,
      });
    }

    offset = boxEnd;
  }

  return exactlyOneSlot(matches);
}

function locateJPEGProofSlot(bytes) {
  if (bytes.length < 2 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw new Error("missing proof slot");
  }

  let offset = 2;
  const matches = [];

  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) {
      break;
    }

    let markerOffset = offset;
    while (markerOffset < bytes.length && bytes[markerOffset] === 0xff) {
      markerOffset += 1;
    }
    if (markerOffset >= bytes.length) {
      break;
    }

    const marker = bytes[markerOffset];
    offset = markerOffset + 1;

    if (marker === 0xd9 || marker === 0xda) {
      break;
    }
    if ((marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) {
      continue;
    }

    if (offset + 2 > bytes.length) {
      break;
    }

    const segmentLength = readUInt16BE(bytes, offset);
    const segmentStart = markerOffset - 1;
    const payloadOffset = offset + 2;
    const segmentEnd = offset + segmentLength;
    if (segmentLength < 2 || segmentEnd > bytes.length) {
      break;
    }

    if (
      marker === 0xeb &&
      segmentLength === TAP_PROOF_SLOT.payloadByteCount + 2 &&
      sameBytes(bytes.subarray(payloadOffset, payloadOffset + MAGIC.length), MAGIC)
    ) {
      matches.push({
        kind: "jpeg-app11-proof-slot",
        containerOffset: segmentStart,
        containerLength: segmentEnd - segmentStart,
        payloadOffset,
        payloadLength: segmentEnd - payloadOffset,
      });
    }

    offset = segmentEnd;
  }

  return exactlyOneSlot(matches);
}

function exactlyOneSlot(matches) {
  if (matches.length !== 1) {
    throw new Error(`expected exactly one TAP proof slot; found ${matches.length}`);
  }
  const slot = matches[0];
  if (slot.payloadLength !== TAP_PROOF_SLOT.payloadByteCount) {
    throw new Error("unexpected proof slot length");
  }
  return slot;
}

function asBytes(input) {
  if (input instanceof Uint8Array) {
    return input;
  }
  if (input instanceof ArrayBuffer) {
    return new Uint8Array(input);
  }
  throw new TypeError("expected Uint8Array or ArrayBuffer");
}

function ascii(bytes, offset, length) {
  let value = "";
  for (let index = 0; index < length; index += 1) {
    value += String.fromCharCode(bytes[offset + index]);
  }
  return value;
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

function sameBytes(lhs, rhs) {
  if (lhs.length !== rhs.length) {
    return false;
  }
  for (let index = 0; index < lhs.length; index += 1) {
    if (lhs[index] !== rhs[index]) {
      return false;
    }
  }
  return true;
}

function readUInt16BE(bytes, offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function readUInt32BE(bytes, offset) {
  return (
    (bytes[offset] * 0x1000000) +
    ((bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3])
  ) >>> 0;
}

function readUInt64BE(bytes, offset) {
  let value = 0n;
  for (let index = 0; index < 8; index += 1) {
    value = (value << 8n) | BigInt(bytes[offset + index]);
  }
  return value;
}

function writeUInt32BE(bytes, offset, value) {
  bytes[offset] = (value >>> 24) & 0xff;
  bytes[offset + 1] = (value >>> 16) & 0xff;
  bytes[offset + 2] = (value >>> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

function base64URL(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  const base64 = globalThis.btoa
    ? globalThis.btoa(binary)
    : Buffer.from(bytes).toString("base64");
  return base64.replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}
