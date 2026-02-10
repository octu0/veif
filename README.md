# veif


> [!IMPORTANT]
> Work In Progress


**veif** is a high-performance, multi-resolution image format.

The core philosophy of **veif** is speed and efficiency—not just in compression, but in distribution.

## Motivation

In modern web services and applications, handling user-uploaded images typically requires generating multiple static files for different display sizes (e.g., `original.jpg`, `large.jpg`, `medium.jpg`, `thumbnail.jpg`).

This traditional approach has significant drawbacks:
1.  **Storage Redundancy**: Storing multiple versions of the same image wastes disk space.
2.  **Computational Cost**: The server must decode, resize, and re-encode the source image multiple times to generate these variants.
3.  **Management Complexity**: Managing multiple file artifacts for a single logical image increases system complexity.

## The Solution: One Master File, Multiple Resolutions

**veif** solves this by adopting a multi-resolution architecture, optimized for high-speed processing.

![figure0](docs/fig0.jpg)

With **veif**, you generate **one single master file**. The server stores only this file.
When a client needs a specific resolution, the server (or the application logic) simply extracts the necessary data layers from the master file.

*   Need a **Thumbnail**? -> Extract **Layer 0** only.
*   Need a **Preview**? -> Extract **Layer 0 + Layer 1**.
*   Need **Full Detail**? -> Extract **All Layers**.

This approach eliminates the need for server-side resizing or re-compression. The "transcoding" process is replaced by efficient binary slicing (demuxing), drastically reducing server CPU load and storage requirements.

| Layer | Resolution | Size | Image |
| :--- | :--- | :--- | :--- |
| Layer0 | 1/4 | 11.24KB | ![Layer0](docs/out_layer0.png) |
| Layer1 | 1/2 | 21.39KB | ![Layer1](docs/out_layer1.png) |
| Layer2 | 1 | 24.73KB | ![Layer2](docs/out_layer2.png) |
| original | 1 | 225KB | ![original](docs/src.png) |

## Internals

- YCbCr 4:2:0
- Multi-Resolution Discrete Wavelet Transform (LeGall 5/3)
  - Global DWT (Full frame transform, no block artifacts)
  - 3-Layer Progressive Encoding
    - Layer 0: Thumbnail (Base LL band)
    - Layer 1: Medium Quality (Adds HL, LH, HH of level 1)
    - Layer 2: High Quality (Adds HL, LH, HH of level 0)
- Content-Adaptive Bit-shift Quantization
- Unified Block RLE / Rice coding
  - Signed integer mapping (Zigzag mapping) for efficient Rice coding
- Virtual Buffer based CBR (Rate Controller)

## CLI Usage

```bash
$ swift run -c release example ./docs/src.png /path/to/output/dir
```

## License

MIT
