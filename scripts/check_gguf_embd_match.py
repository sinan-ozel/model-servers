#!/usr/bin/env python3
"""Verify a text model's embedding size matches its mmproj's projection dim.

llama.cpp's clip encoder projects vision embeddings into the text model's
embedding space. If the two sizes don't match, the model loads but produces
garbage (or crashes) for vision inputs. This reads only the GGUF metadata
header of each file (not the tensor data), so it's fast even for
multi-gigabyte model files.

Usage: check_gguf_embd_match.py <text_model.gguf> <mmproj.gguf>
"""
import struct
import sys

_FIXED_SIZES = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}


def _read_string(f):
    (length,) = struct.unpack('<Q', f.read(8))
    return f.read(length).decode('utf-8', errors='replace')


def _read_value(f, value_type):
    if value_type == 8:  # string
        return _read_string(f)
    if value_type == 9:  # array
        (elem_type,) = struct.unpack('<I', f.read(4))
        (length,) = struct.unpack('<Q', f.read(8))
        return [_read_value(f, elem_type) for _ in range(length)]
    fmt, size = {
        0: ('<B', 1), 1: ('<b', 1), 2: ('<H', 2), 3: ('<h', 2),
        4: ('<I', 4), 5: ('<i', 4), 6: ('<f', 4), 7: ('<?', 1),
        10: ('<Q', 8), 11: ('<q', 8), 12: ('<d', 8),
    }[value_type]
    return struct.unpack(fmt, f.read(size))[0]


def _skip_value(f, value_type):
    if value_type == 8:
        _read_string(f)
    elif value_type == 9:
        (elem_type,) = struct.unpack('<I', f.read(4))
        (length,) = struct.unpack('<Q', f.read(8))
        for _ in range(length):
            _skip_value(f, elem_type)
    else:
        f.read(_FIXED_SIZES[value_type])


def read_gguf_metadata(path, wanted_keys):
    """Read only the requested keys out of a GGUF file's metadata header."""
    found = {}
    with open(path, 'rb') as f:
        magic = f.read(4)
        if magic != b'GGUF':
            raise ValueError(f"{path}: not a GGUF file (bad magic {magic!r})")
        f.read(4)   # version, unused
        f.read(8)   # tensor_count, unused
        (kv_count,) = struct.unpack('<Q', f.read(8))
        for _ in range(kv_count):
            key = _read_string(f)
            (value_type,) = struct.unpack('<I', f.read(4))
            if key in wanted_keys:
                found[key] = _read_value(f, value_type)
                if len(found) == len(wanted_keys):
                    break
            else:
                _skip_value(f, value_type)
    return found


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <text_model.gguf> <mmproj.gguf>", file=sys.stderr)
        sys.exit(2)

    text_path, mmproj_path = sys.argv[1], sys.argv[2]

    arch = read_gguf_metadata(text_path, {'general.architecture'}).get('general.architecture')
    if not arch:
        print(f"❌ Could not read general.architecture from {text_path}", file=sys.stderr)
        sys.exit(1)

    embd_key = f'{arch}.embedding_length'
    n_embd = read_gguf_metadata(text_path, {embd_key}).get(embd_key)
    if n_embd is None:
        print(f"❌ Could not read {embd_key} from {text_path}", file=sys.stderr)
        sys.exit(1)

    proj_key = 'clip.vision.projection_dim'
    proj_dim = read_gguf_metadata(mmproj_path, {proj_key}).get(proj_key)
    if proj_dim is None:
        print(f"❌ Could not read {proj_key} from {mmproj_path}", file=sys.stderr)
        sys.exit(1)

    if n_embd != proj_dim:
        print(
            f"❌ Embedding size mismatch: {text_path} has {embd_key}={n_embd}, "
            f"but {mmproj_path} has {proj_key}={proj_dim}. "
            "The mmproj projector output must match the text model's embedding size, "
            "or vision inputs will produce garbage output.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"✓ Embedding sizes match: {embd_key}={n_embd} == {proj_key}={proj_dim}")


if __name__ == '__main__':
    main()
