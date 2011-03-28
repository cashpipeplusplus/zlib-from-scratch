/*
 * This file is a part of ZlibFromScratch,
 * an open-source ActionScript decompression library.
 * Copyright (C) 2011 - Joey Parrish
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 * 
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library.
 * If not, see <http://www.gnu.org/licenses/>.
 */
package com.zlibfromscratch
{
	import com.zlibfromscratch.internal.Adler32;
	import com.zlibfromscratch.internal.CRC32;
	import com.zlibfromscratch.internal.DisposeUtil;
	import com.zlibfromscratch.internal.HuffmanDecoder;
	import com.zlibfromscratch.internal.IChecksum;
	
	import flash.utils.ByteArray;
	
	/**
	 * The ZlibDecoder class is a decompressor that supports both zlib and
	 * gzip formats.
	 * 
	 * <p>Advantages over <code>ByteArray.uncompress()</code>:</p>
	 * 
	 * <p>
	 *   <ol>
	 *     <li>Compressed data does not need to be present all at once.
	 *         It can be fed in a little at a time as it becomes available,
	 *         for example, from a <code>Socket</code>.
	 *         By contrast, <code>ByteArray.uncompress()</code> would throw
	 *         an error if the data were incomplete.</li>
	 *     <li>Output is generated as the corresponding input is fed in.
	 *         Output can be streamed.</li>
	 *     <li>If the input buffer has extra data, the excess is not lost.
	 *         This allows, for example, multiple zlib-formatted compressed
	 *         messages to be concatenated without size information.
	 *         By contrast, <code>ByteArray.uncompress()</code> would discard
	 *         any data beyond the first message.</li>
	 *     <li>Gzip format is supported directly even when targeting Flash 9.
	 *         By contrast, <code>ByteArray.uncompress()</code> requires
	 *         Flash 10 or AIR, and further requires that the caller first
	 *         parse and remove the gzip metadata.</li>
	 *     <li>The compression format is automatically detected.</li>
	 *   </ol>
	 * </p>
	 * 
	 * @example The following is a typical usage pattern:
	 * 
	 * <listing version="3.0">
	 * 
	 * var input:ByteArray = new ByteArray;
	 * var output:ByteArray = new ByteArray;
	 * var z:ZlibDecoder = new ZlibDecoder;
	 * 
	 * // When data becomes available in input:
	 * 
	 * var bytesRead:uint = z.feed(input, output);
	 * input = ZlibUtil.removeBeginning(input, bytesRead); // remove consumed data
	 * if (z.lastError == ZlibDecoderError.NeedMoreData) {
	 *   // Wait for more data in input.
	 * } else if (z.lastError == ZlibDecoderError.NoError) {
	 *   // Decoding is done.
	 *   // The uncompressed message is in the output ByteArray.
	 *   // Any excess data that was not a part of the
	 *   // compressed message is in the input ByteArray.
	 * } else {
	 *   // An error occurred while processing the input data.
	 * }
	 * </listing>
	 */
	public class ZlibDecoder
	{
		// Embedded lookup tables for length and distance codes, to quickly find the
		// number of extra bits and base values.
		[Embed(source='/assets/lcodes.extra_bits', mimeType="application/octet-stream")]
		private static var _lcodes_extra_bits_class:Class;
		private static var _lcodes_extra_bits:ByteArray = new _lcodes_extra_bits_class;
		
		[Embed(source='/assets/lcodes.base_values', mimeType="application/octet-stream")]
		private static var _lcodes_base_values_class:Class;
		private static var _lcodes_base_values:ByteArray = new _lcodes_base_values_class;
		
		[Embed(source='/assets/dcodes.extra_bits', mimeType="application/octet-stream")]
		private static var _dcodes_extra_bits_class:Class;
		private static var _dcodes_extra_bits:ByteArray = new _dcodes_extra_bits_class;
		
		[Embed(source='/assets/dcodes.base_values', mimeType="application/octet-stream")]
		private static var _dcodes_base_values_class:Class;
		private static var _dcodes_base_values:ByteArray = new _dcodes_base_values_class;
		
		// Embedded lookup table for unmixing the code code lengths. (not a typo)
		[Embed(source='/assets/deflate_length_unmix', mimeType="application/octet-stream")]
		private static var _deflate_length_unmix_class:Class;
		private static var _deflate_length_unmix:ByteArray = new _deflate_length_unmix_class;
		
		// Embedded code length values for initializing the static Huffman tables.
		[Embed(source='/assets/deflate_fixed_lengths', mimeType="application/octet-stream")]
		private static var _deflate_fixed_lengths_class:Class;
		private static var _deflate_fixed_lengths:ByteArray = new _deflate_fixed_lengths_class;
		
		private static const STATE_HEADER:uint = 0;
		private static const STATE_BODY:uint = 1;
		private static const STATE_TRAILER:uint = 2;
		private static const STATE_DONE:uint = 3;
		private static const STATE_GZIP_EXTRA_HEADERS:uint = 4;
		
		private static const BLOCK_TYPE_UNCOMPRESSED:uint = 0;
		private static const BLOCK_TYPE_FIXED:uint = 1;
		private static const BLOCK_TYPE_DYNAMIC:uint = 2;
		private static const BLOCK_TYPE_NONE:uint = 3;
		
		private static const BLOCK_STATE_NEED_LEN:uint = 0;
		private static const BLOCK_STATE_COPYING:uint = 1;
		
		private static const BLOCK_STATE_NUM_CODES:uint = 2;
		private static const BLOCK_STATE_GET_CODE_CODES:uint = 3;
		private static const BLOCK_STATE_GET_CODES:uint = 4;
		private static const BLOCK_STATE_HUFFMAN_LCODE:uint = 5;
		private static const BLOCK_STATE_HUFFMAN_DCODE:uint = 6;
		
		private var _main_state:uint;
		private var _lastError:uint;
		
		private var _header_pos:uint;
		private var _header_cmf:uint;
		private var _header_flg:uint;
		private var _header_gzip:Boolean;
		private var _extra_header_bytes_left:int;
		private var _header_tmp:uint;
		
		private var _body_bits:uint;
		private var _num_body_bits:uint;
		private var _block_type:uint;
		private var _final_block:Boolean;
		private var _block_state:uint;
		
		private var _uncompressed_bytes_left:uint;
		private var _uncompressed_tmp:uint;
		
		private var _huffman_num_lcodes:uint;
		private var _huffman_num_dcodes:uint;
		private var _huffman_num_code_codes:uint;
		private var _huffman_repeat_length:uint;
		private var _huffman_tmp_pos:uint;
		private var _huffman_tmp_lengths:Array;
		private var _huffman_table_0:HuffmanDecoder;
		private var _huffman_table_1:HuffmanDecoder;
		private var _huffman_table_2:HuffmanDecoder;
		private var _huffman_table_fixed:HuffmanDecoder;
		
		private var _trailer_pos:uint;
		private var _trailer_checksum_tmp:uint;
		private var _trailer_size_tmp:uint;
		
		private var _verifyChecksum:Boolean;
		private var _checksum:IChecksum;
		
		/**
		 * Constructor.
		 * 
		 * @param verifyChecksum
		 *   If <code>true</code>, verify the checksum of the uncompressed
		 *   data after decompression is complete.
		 *   If <code>false</code>, skip the checksum calculation and
		 *   verification, which may improve decompression speed.
		 */
		public function ZlibDecoder(verifyChecksum:Boolean=false)
		{
			reset(verifyChecksum);
		}
		
		/**
		 * Reset the decoder's internal state.
		 * After calling <code>reset()</code>, the decoder is in a
		 * pristine state, equivalent to a newly constructed object.
		 * Must be called between reading one compressed message
		 * and beginning to read another.
		 * 
		 * @param verifyChecksum
		 *   If <code>true</code>, verify the checksum of the uncompressed
		 *   data after decompression is complete.
		 *   If <code>false</code>, skip the checksum calculation and
		 *   verification, which may improve decompression speed.
		 */
		public function reset(verifyChecksum:Boolean=false):void
		{
			dispose();
			_main_state = STATE_HEADER;
			_lastError = ZlibDecoderError.NeedMoreData;
			_header_pos = 0;
			_body_bits = 0;
			_num_body_bits = 0;
			_block_type = BLOCK_TYPE_NONE;
			_trailer_pos = 0;
			_verifyChecksum = verifyChecksum;
			_checksum = null;
			_huffman_table_0 = null;
			_huffman_table_1 = null;
			_huffman_table_2 = null;
			_huffman_table_fixed = null;
			_huffman_tmp_lengths = null;
		}
		
		/**
		 * Wipe the decoder's internal state to reclaim memory.
		 * Call <code>dispose()</code> when the object is no longer needed.
		 */
		public function dispose():void
		{
			_checksum = null;
			if (_huffman_table_0) _huffman_table_0.dispose();
			_huffman_table_0 = null;
			if (_huffman_table_1) _huffman_table_1.dispose();
			_huffman_table_1 = null;
			if (_huffman_table_2) _huffman_table_2.dispose();
			_huffman_table_2 = null;
			if (_huffman_table_fixed) _huffman_table_fixed.dispose();
			_huffman_table_fixed = null;
			DisposeUtil.genericDispose(_huffman_tmp_lengths);
			_huffman_tmp_lengths = null;
		}
		
		/**
		 * Feed compressed input into the decoder and receive uncompressed
		 * output back.
		 * 
		 * @param input
		 *   The compressed input data.  Data is read from the
		 *   <code>ByteArray</code> starting at position 0.
		 * @param output
		 *   The uncompressed output data.  Data is written to the
		 *   <code>ByteArray</code>'s current position.  The same
		 *   <code>output</code> object must be provided to each call to
		 *   <code>feed()</code> until <code>reset()</code> is called to
		 *   begin a new message.
		 * 
		 * @return The number of bytes of input used.
		 *   Always check <code>lastError</code> for status information.
		 * 
		 * @see #lastError
		 * @see ZlibDecoderError
		 */
		public function feed(input:ByteArray, output:ByteArray):uint
		{
			if (_lastError != ZlibDecoderError.NeedMoreData) {
				return 0;
			}
			if (input.length == 0) {
				return 0;
			}
			
			input.position = 0;
			var previousPosition:uint;
			const more:uint = ZlibDecoderError.NeedMoreData;
			
			do {
				previousPosition = input.position;
				
				switch (_main_state) {
					case STATE_HEADER:
						readHeader(input);
						break;
					case STATE_GZIP_EXTRA_HEADERS:
						readGzipExtraHeaders(input);
						break;
					case STATE_BODY:
						readBody(input, output);
						break;
					case STATE_TRAILER:
						readTrailer(input);
						break;
					default:
						trace("Invalid state: " + _main_state);
						_lastError = ZlibDecoderError.InternalError;
						break;
				}
			} while (input.position != previousPosition && input.bytesAvailable && _main_state != STATE_DONE && _lastError == more);
			
			if (_lastError == more) {
				if (input.position == 0) {
					trace("Internal error: no data consumed, no error set!");
					_lastError = ZlibDecoderError.InternalError;
				} else if (input.bytesAvailable) {
					trace("Internal error: not all input data consumed!");
					_lastError = ZlibDecoderError.InternalError;
				}
			}
			return input.position;
		}
		
		/**
		 * The error code from the last call to <code>feed()</code>.
		 * The value is a constant from the <code>ZlibDecoderError</code>
		 * class.
		 * 
		 * @see ZlibDecoderError
		 * @see #feed()
		 */
		public function get lastError():uint
		{
			return _lastError;
		}
		
		private function readHeader(input:ByteArray):void
		{
			if (_header_pos == 0 && input.bytesAvailable) {
				_header_cmf = input[input.position++];
				_header_pos++;
			}
			if (_header_pos == 1 && input.bytesAvailable) {
				_header_flg = input[input.position++];
				if (_header_cmf == 0x1f && _header_flg == 0x8b) {
					_header_gzip = true;
					if (_verifyChecksum) _checksum = new CRC32;
					_header_pos++;
				} else {
					_header_gzip = false;
					if (_verifyChecksum) _checksum = new Adler32;
					if (checkHeader()) {
						_main_state++;
					}
					return;
				}
			}
			if (_header_pos == 2 && input.bytesAvailable) {
				_header_cmf = input[input.position++];
				_header_pos++;
			}
			if (_header_pos == 3 && input.bytesAvailable) {
				_header_flg = input[input.position++];
				if (checkHeader()) {
					_main_state = STATE_GZIP_EXTRA_HEADERS;
					_header_pos = 0;
					_extra_header_bytes_left = 6;
				}
			}
		}
		
		private function readGzipExtraHeaders(input:ByteArray):void
		{
			while (true) {
				if (_extra_header_bytes_left > 0) {
					if (input.bytesAvailable < _extra_header_bytes_left) {
						// skip as much as we can.
						input.position += input.bytesAvailable;
						_extra_header_bytes_left -= input.bytesAvailable;
						return;
					}
					// skip the rest of these bytes.
					input.position += _extra_header_bytes_left;
					_extra_header_bytes_left = 0;
				} else if (_extra_header_bytes_left < 0) {
					// seek a zero byte.
					while (input.bytesAvailable) {
						if (input[input.position] == 0) {
							break;
						}
						input.position++;
					}
					if (input[input.position] != 0) {
						return;
					}
					input.position++;
					_extra_header_bytes_left = 0;
				}
				
				if (_header_pos == 0) {
					if (_header_flg & 4) {
						if (!input.bytesAvailable) return;
						_header_tmp = input[input.position++];
					}
					_header_pos++;
				}
				if (_header_pos == 1) {
					if (_header_flg & 4) {
						if (!input.bytesAvailable) return;
						_extra_header_bytes_left = (_header_tmp << 8) | input[input.position++];
						_header_pos++;
						continue;
					} else {
						_header_pos++;
					}
				}
				if (_header_pos == 2) {
					_header_pos++;
					if (_header_flg & 8) {
						_extra_header_bytes_left = -1;
						continue;
					}
				}
				if (_header_pos == 3) {
					_header_pos++;
					if (_header_flg & 16) {
						_extra_header_bytes_left = -1;
						continue;
					}
				}
				if (_header_pos == 4) {
					_header_pos++;
					if (_header_flg & 2) {
						_extra_header_bytes_left = 2;
						continue;
					}
				}
				if (_header_pos == 5) {
					_main_state = STATE_BODY;
					return;
				}
			}
		}
		
		private function checkHeader():Boolean
		{
			if (_header_gzip == false) {
				var check:uint = (_header_cmf << 8) | _header_flg;
				if ((check % 31) != 0) {
					// The FCHECK value must be such that CMF and FLG, when viewed as
					// a 16-bit unsigned integer stored in MSB order (CMF*256 + FLG),
					// is a multiple of 31.
					_lastError = ZlibDecoderError.InvalidHeader;
					return false;
				}
				if ((_header_cmf & 0xf) != 8) {
					// This identifies the compression method used in the file. CM = 8
					// denotes the "deflate" compression method with a window size up
					// to 32K.
					_lastError = ZlibDecoderError.UnsupportedFeatures;
					return false;
				}
				if (((_header_cmf >> 4) & 15) > 7) {
					// For CM = 8, CINFO is the base-2 logarithm of the LZ77 window
					// size, minus eight (CINFO=7 indicates a 32K window size). Values
					// of CINFO above 7 are not allowed in this version of the
					// specification.
					_lastError = ZlibDecoderError.InvalidHeader;
					return false;
				}
				if (_header_flg & 0x20) {
					// bit  5       FDICT   (preset dictionary)
					_lastError = ZlibDecoderError.UnsupportedFeatures;
					return false;
				}
				return true;
			} else {
				if (_header_cmf < 8) {
					// CM = 0-7 are reserved.
					_lastError = ZlibDecoderError.InvalidHeader;
					return false;
				}
				if (_header_flg & 0xe0) {
					// bit 5   reserved
					// bit 6   reserved
					// bit 7   reserved
					_lastError = ZlibDecoderError.InvalidHeader;
					return false;
				}
				if (_header_cmf != 8) {
					// CM = 8 denotes the "deflate" compression method,
					// which is the one customarily used by gzip
					_lastError = ZlibDecoderError.UnsupportedFeatures;
					return false;
				}
				return true;
			}
		}
		
		// You may not gather more than 25 bits at a time.
		// These restrictions are not enforced, but must be observed by the caller.
		private function gatherBits(input:ByteArray, numBits:uint):Boolean
		{
			while (_num_body_bits < numBits && input.bytesAvailable) {
				_body_bits |= input[input.position++] << _num_body_bits;
				_num_body_bits += 8;
			}
			return (_num_body_bits >= numBits);
		}
		
		// You must first gatherBits to make sure you have enough bits in store.
		// These restrictions are not enforced, but must be observed by the caller.
		private function eatBits(numBits:uint):uint
		{
			var data:uint = _body_bits & ((1 << numBits) - 1);
			_num_body_bits -= numBits;
			_body_bits >>= numBits;
			return data;
		}
		
		// You must first gatherBits to make sure you have enough bits in store.
		// These restrictions are not enforced, but must be observed by the caller.
		private function peekBits(numBits:uint, offset:uint=0):uint
		{
			return (_body_bits >> offset) & ((1 << numBits) - 1);
		}
		
		private function readBody(input:ByteArray, output:ByteArray):void
		{
			if (_block_type == BLOCK_TYPE_NONE) {
				if (!gatherBits(input, 3)) return;
				_final_block = eatBits(1) != 0;
				_block_type = eatBits(2);
				switch (_block_type) {
					case BLOCK_TYPE_UNCOMPRESSED:
						_num_body_bits = 0;
						_body_bits = 0;
						_block_state = BLOCK_STATE_NEED_LEN;
						_uncompressed_bytes_left = 4;
						break;
					case BLOCK_TYPE_FIXED:
						if (!_huffman_table_fixed) _huffman_table_fixed = new HuffmanDecoder(_deflate_fixed_lengths);
						_block_state = BLOCK_STATE_HUFFMAN_LCODE;
						break;
					case BLOCK_TYPE_DYNAMIC:
						_block_state = BLOCK_STATE_NUM_CODES;
						break;
				}
			}
			
			switch (_block_type) {
				case BLOCK_TYPE_UNCOMPRESSED:
					readUncompressedBlock(input, output);
					break;
				case BLOCK_TYPE_FIXED:
					readFixedBlock(input, output);
					break;
				case BLOCK_TYPE_DYNAMIC:
					readDynamicBlock(input, output);
					break;
				default:
					trace("Invalid block type: " + _block_type);
					_lastError = ZlibDecoderError.InvalidData;
					break;
			}
			
			if (_block_type == BLOCK_TYPE_NONE && _final_block) {
				_main_state++;
				// put back any extra whole bytes we may have read in as bits.
				input.position -= (_num_body_bits >> 3);
				_num_body_bits = 0;
				_body_bits = 0;
			}
		}
		
		private function readUncompressedBlock(input:ByteArray, output:ByteArray):void
		{
			if (_block_state == BLOCK_STATE_NEED_LEN) {
				if (_uncompressed_bytes_left == 4 && input.bytesAvailable) {
					_uncompressed_tmp = input[input.position++] << 16;
					_uncompressed_bytes_left--;
				}
				if (_uncompressed_bytes_left == 3 && input.bytesAvailable) {
					_uncompressed_tmp |= input[input.position++] << 24;
					_uncompressed_bytes_left--;
				}
				if (_uncompressed_bytes_left == 2 && input.bytesAvailable) {
					_uncompressed_tmp |= input[input.position++];
					_uncompressed_bytes_left--;
				}
				if (_uncompressed_bytes_left == 1 && input.bytesAvailable) {
					_uncompressed_tmp |= input[input.position++] << 8;
					_uncompressed_bytes_left--;
					
					_uncompressed_bytes_left = (_uncompressed_tmp >> 16) & 0xffff;
					var check:uint = (~_uncompressed_tmp) & 0xffff; // should be 1's complement of _uncompressed_bytes_left
					if (_uncompressed_bytes_left != check) {
						trace("Invalid uncompressed block header.");
						_lastError = ZlibDecoderError.InvalidData;
						return;
					}
					_block_state = BLOCK_STATE_COPYING;
				}
			}
			if (_block_state == BLOCK_STATE_COPYING) {
				while (_uncompressed_bytes_left && input.bytesAvailable) {
					var grab:uint = input.bytesAvailable;
					if (grab > _uncompressed_bytes_left) grab = _uncompressed_bytes_left;
					output.writeBytes(input, input.position, grab);
					if (_checksum) _checksum.feed(input, input.position, grab);
					input.position += grab;
					_uncompressed_bytes_left -= grab;
				}
				if (_uncompressed_bytes_left == 0) {
					_block_type = BLOCK_TYPE_NONE;
				}
			}
		}
		
		private function bitsIntoTable(input:ByteArray, table:HuffmanDecoder, what:String):uint
		{
			var bitsUsed:uint;
			var bits:uint;
			
			if (gatherBits(input, table.maxLength)) {
				bits = table.maxLength;
			} else {
				bits = _num_body_bits;
			}
			
			bitsUsed = table.bitsUsed(peekBits(bits));
			
			if (bitsUsed == 0 || bitsUsed > bits) {
				if (bits == table.maxLength) {
					trace("Unable to find valid " + what + ".");
					_lastError = ZlibDecoderError.InvalidData;
				}
				return 0;
			}
			
			return bitsUsed;
		}
		
		private function readFixedBlock(input:ByteArray, output:ByteArray):void
		{
			var bits:uint;
			var symbol:uint;
			var length:uint;
			var copies:uint;
			var extraBits:uint;
			var baseValue:uint;
			var i:uint;
			var distance:uint;
			var spos:uint;
			var available:uint;
			
			while (_block_state == BLOCK_STATE_HUFFMAN_LCODE || _block_state == BLOCK_STATE_HUFFMAN_DCODE) {
				while (_block_state == BLOCK_STATE_HUFFMAN_LCODE) {
					bits = bitsIntoTable(input, _huffman_table_fixed, "lcode");
					if (bits == 0) return;
					symbol = _huffman_table_fixed.decode(peekBits(bits));
					if (symbol < 256) {
						// literal byte.
						output.writeByte(symbol);
						if (_checksum) _checksum.feedByte(symbol);
						eatBits(bits);
					} else if (symbol == 256) {
						// end of block.
						eatBits(bits);
						_block_type = BLOCK_TYPE_NONE;
						return;
					} else if (symbol < 286) {
						extraBits = _lcodes_extra_bits[symbol];
						baseValue = (_lcodes_base_values[symbol << 1] << 8) | _lcodes_base_values[(symbol << 1) + 1];
						
						if (!gatherBits(input, bits + extraBits)) return;
						eatBits(bits);
						_huffman_repeat_length = baseValue + eatBits(extraBits); // length of the sequence to be repeated.
						_block_state = BLOCK_STATE_HUFFMAN_DCODE;
					} else {
						trace("Invalid literal/length symbol: " + symbol);
						_lastError = ZlibDecoderError.InvalidData;
						return;
					}
				}
				
				if (!gatherBits(input, 5)) return;
				symbol = peekBits(5);
				// reverse the bit order of a fixed-length 5-bit number:
				symbol = ((symbol & 1) << 4) | ((symbol & 2) << 2) | (symbol & 4) | ((symbol & 8) >> 2) | ((symbol & 16) >> 4);
				if (symbol < 30) {
					extraBits = _dcodes_extra_bits[symbol];
					baseValue = (_dcodes_base_values[symbol << 1] << 8) | _dcodes_base_values[(symbol << 1) + 1];
					
					if (!gatherBits(input, 5 + extraBits)) return;
					eatBits(5);
					distance = baseValue + eatBits(extraBits);
					spos = output.position - distance;
					while (_huffman_repeat_length) {
						available = output.length - spos;
						if (available > _huffman_repeat_length) available = _huffman_repeat_length;
						output.writeBytes(output, spos, available);
						if (_checksum) _checksum.feed(output, spos, available);
						_huffman_repeat_length -= available;
					}
					_block_state = BLOCK_STATE_HUFFMAN_LCODE;
				} else {
					trace("Invalid distance symbol: " + symbol);
					_lastError = ZlibDecoderError.InvalidData;
					return;
				}
			}
		}
		
		private function readDynamicBlock(input:ByteArray, output:ByteArray):void
		{
			var bits:uint;
			var symbol:uint;
			var length:uint;
			var copies:uint;
			var extraBits:uint;
			var baseValue:uint;
			var i:uint;
			var distance:uint;
			var spos:uint;
			var available:uint;
			
			if (_block_state == BLOCK_STATE_NUM_CODES) {
				if (!gatherBits(input, 14)) return;
				_huffman_num_lcodes = eatBits(5) + 257;
				_huffman_num_dcodes = eatBits(5) + 1;
				_huffman_num_code_codes = eatBits(4) + 4;
				_block_state = BLOCK_STATE_GET_CODE_CODES;
				DisposeUtil.genericDispose(_huffman_tmp_lengths);
				_huffman_tmp_lengths = [];
				for (i = 0; i < 19; i++) {
					_huffman_tmp_lengths.push(0);
				}
				_huffman_tmp_pos = 0;
			}
			if (_block_state == BLOCK_STATE_GET_CODE_CODES) {
				while (_huffman_tmp_pos < _huffman_num_code_codes) {
					if (!gatherBits(input, 3)) return;
					_huffman_tmp_lengths[_deflate_length_unmix[_huffman_tmp_pos]] = eatBits(3);
					_huffman_tmp_pos++;
				}
				if (_huffman_table_0) _huffman_table_0.dispose();
				_huffman_table_0 = new HuffmanDecoder(_huffman_tmp_lengths);
				_block_state = BLOCK_STATE_GET_CODES;
				DisposeUtil.genericDispose(_huffman_tmp_lengths);
				_huffman_tmp_lengths = [];
				_huffman_tmp_pos = 0;
			}
			if (_block_state == BLOCK_STATE_GET_CODES) {
				while (_huffman_tmp_pos < _huffman_num_lcodes + _huffman_num_dcodes) {
					bits = bitsIntoTable(input, _huffman_table_0, "code code");
					if (bits == 0) return;
					symbol = _huffman_table_0.decode(peekBits(bits));
					if (symbol < 16) {
						eatBits(bits);
						length = symbol;
						copies = 1;
					} else if (symbol < 19) {
						if (symbol == 16) {
							if (!gatherBits(input, bits + 2)) return;
							eatBits(bits);
							length = _huffman_tmp_lengths[_huffman_tmp_lengths.length - 1];
							copies = eatBits(2) + 3;
						} else if (symbol == 17) {
							if (!gatherBits(input, bits + 3)) return;
							eatBits(bits);
							length = 0;
							copies = eatBits(3) + 3;
						} else if (symbol == 18) {
							if (!gatherBits(input, bits + 7)) return;
							eatBits(bits);
							length = 0;
							copies = eatBits(7) + 11;
						}
					} else {
						trace("Invalid code symbol: " + symbol);
						_lastError = ZlibDecoderError.InvalidData;
						return;
					}
					
					for (i = 0; i < copies; i++) {
						_huffman_tmp_lengths.push(length);
					}
					_huffman_tmp_pos += copies;
				}
				if (!_huffman_tmp_lengths[256]) {
					trace("Invalid data, missing end of block symbol.");
					_lastError = ZlibDecoderError.InvalidData;
					return;
				}
				_huffman_table_1 = new HuffmanDecoder(_huffman_tmp_lengths, 0, _huffman_num_lcodes);
				_huffman_table_2 = new HuffmanDecoder(_huffman_tmp_lengths, _huffman_num_lcodes, _huffman_num_dcodes);
				_block_state = BLOCK_STATE_HUFFMAN_LCODE;
			}
			while (_block_state == BLOCK_STATE_HUFFMAN_LCODE || _block_state == BLOCK_STATE_HUFFMAN_DCODE) {
				while (_block_state == BLOCK_STATE_HUFFMAN_LCODE) {
					bits = bitsIntoTable(input, _huffman_table_1, "lcode");
					if (bits == 0) return;
					symbol = _huffman_table_1.decode(peekBits(bits));
					if (symbol < 256) {
						// literal byte.
						output.writeByte(symbol);
						if (_checksum) _checksum.feedByte(symbol);
						eatBits(bits);
					} else if (symbol == 256) {
						// end of block.
						eatBits(bits);
						_block_type = BLOCK_TYPE_NONE;
						return;
					} else if (symbol < 286) {
						extraBits = _lcodes_extra_bits[symbol];
						baseValue = (_lcodes_base_values[symbol << 1] << 8) | _lcodes_base_values[(symbol << 1) + 1];
						
						if (!gatherBits(input, bits + extraBits)) return;
						eatBits(bits);
						_huffman_repeat_length = baseValue + eatBits(extraBits); // length of the sequence to be repeated.
						_block_state = BLOCK_STATE_HUFFMAN_DCODE;
					} else {
						trace("Invalid literal/length symbol: " + symbol);
						_lastError = ZlibDecoderError.InvalidData;
						return;
					}
				}
				
				bits = bitsIntoTable(input, _huffman_table_2, "dcode");
				if (bits == 0) return;
				symbol = _huffman_table_2.decode(peekBits(bits));
				if (symbol < 30) {
					extraBits = _dcodes_extra_bits[symbol];
					baseValue = (_dcodes_base_values[symbol << 1] << 8) | _dcodes_base_values[(symbol << 1) + 1];
					
					if (!gatherBits(input, bits + extraBits)) return;
					eatBits(bits);
					distance = baseValue + eatBits(extraBits);
					spos = output.position - distance;
					while (_huffman_repeat_length) {
						available = output.length - spos;
						if (available > _huffman_repeat_length) available = _huffman_repeat_length;
						output.writeBytes(output, spos, available);
						if (_checksum) _checksum.feed(output, spos, available);
						_huffman_repeat_length -= available;
					}
					_block_state = BLOCK_STATE_HUFFMAN_LCODE;
				} else {
					trace("Invalid distance symbol: " + symbol);
					_lastError = ZlibDecoderError.InvalidData;
					return;
				}
			}
		}
		
		private function readTrailer(input:ByteArray):void
		{
			if (_trailer_pos == 0 && input.bytesAvailable) {
				_trailer_checksum_tmp = input[input.position++] << 24;
				_trailer_pos++;
			}
			if (_trailer_pos == 1 && input.bytesAvailable) {
				_trailer_checksum_tmp |= input[input.position++] << 16;
				_trailer_pos++;
			}
			if (_trailer_pos == 2 && input.bytesAvailable) {
				_trailer_checksum_tmp |= input[input.position++] << 8;
				_trailer_pos++;
			}
			if (_trailer_pos == 3 && input.bytesAvailable) {
				_trailer_checksum_tmp |= input[input.position++];
				if (_header_gzip == false) {
					if (checkTrailer()) {
						_lastError = ZlibDecoderError.NoError;
						_main_state++;
					}
				} else {
					// swap the bytes if it's a gzip header.
					// our crc32 implementation spits out in the opposite byte order.
					_trailer_checksum_tmp = (_trailer_checksum_tmp & 0xff) << 24 | (_trailer_checksum_tmp & 0xff00) << 8 |
					                        (_trailer_checksum_tmp & 0xff0000) >> 8 | (_trailer_checksum_tmp & 0xff000000) >> 24;
					_trailer_pos++;
				}
			}
			if (_trailer_pos == 4 && input.bytesAvailable) {
				_trailer_size_tmp = input[input.position++];
				_trailer_pos++;
			}
			if (_trailer_pos == 5 && input.bytesAvailable) {
				_trailer_size_tmp |= input[input.position++] << 8;
				_trailer_pos++;
			}
			if (_trailer_pos == 6 && input.bytesAvailable) {
				_trailer_size_tmp |= input[input.position++] << 16;
				_trailer_pos++;
			}
			if (_trailer_pos == 7 && input.bytesAvailable) {
				_trailer_size_tmp |= input[input.position++] << 24;
				if (checkTrailer()) {
					_lastError = ZlibDecoderError.NoError;
					_main_state++;
				}
			}
		}
		
		private function checkTrailer():Boolean
		{
			if (_verifyChecksum) {
				if (_trailer_checksum_tmp != _checksum.checksum) {
					_lastError = ZlibDecoderError.ChecksumMismatch;
					return false;
				}
				if (_header_gzip && _trailer_size_tmp != _checksum.bytesAccumulated) {
					_lastError = ZlibDecoderError.ChecksumMismatch;
					return false;
				}
			}
			return true;
		}
	}
}
