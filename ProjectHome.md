A decompression library which supports zlib and gzip formats, written from scratch in AS3.


---


Advantages over `ByteArray.uncompress()`:

  * Compressed data does not need to be present all at once. It can be fed in a little at a time as it becomes available, for example, from a `Socket`. By contrast, `ByteArray.uncompress()` would throw an error if the data were incomplete.
  * Output is generated as the corresponding input is fed in. Output can be streamed.
  * If the input buffer has extra data, the excess is not lost. This allows, for example, multiple zlib-formatted compressed messages to be concatenated without size information. By contrast, `ByteArray.uncompress()` would discard any data beyond the first message.
  * Gzip format is supported directly even when targeting Flash 9. By contrast, `ByteArray.uncompress()` requires Flash 10 or AIR, and further requires that the caller first parse and remove the gzip metadata.
  * The compression format is automatically detected.


---

The following is a typical usage pattern:
```

  var input:ByteArray = new ByteArray;
  var output:ByteArray = new ByteArray;
  var z:ZlibDecoder = new ZlibDecoder;

  // When data becomes available in input:
  var bytesRead:uint = z.feed(input, output);
  input = ZlibUtil.removeBeginning(input, bytesRead); // remove consumed data
  if (z.lastError == ZlibDecoderError.NeedMoreData) {
    // Wait for more data in input.
  } else if (z.lastError == ZlibDecoderError.NoError) {
    // Decoding is done.
    // The uncompressed message is in the output ByteArray.
    // Any excess data that was not a part of the
    // compressed message is in the input ByteArray.
  } else {
    // An error occurred while processing the input data.
  }

```