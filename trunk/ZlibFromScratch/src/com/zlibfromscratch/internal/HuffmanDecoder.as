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
package com.zlibfromscratch.internal
{
	/** @private For internal use only. */
	public class HuffmanDecoder
	{
		private var _table:Array;
		private var _max_length:uint;
		
		public function HuffmanDecoder(code_lengths:*, offset:uint = 0, length:uint = 0)
		{
			var symbol:uint;
			var code:uint;
			var sorted_symbols:Array = [];
			var length_count:Array = [];
			var n:uint;
			var len:uint;
			var i:uint;
			var j:uint;
			var set:Array;
			var max_code:uint;
			var k:uint;
			
			if (offset > code_lengths.length) {
				throw new Error("Invalid offset in Huffman decoder construction.");
			}
			
			if (length == 0) length = code_lengths.length - offset;
			
			for (symbol = 0; symbol < length; symbol++) {
				len = code_lengths[symbol + offset];
				if (!length_count[len]) length_count[len] = 1;
				else length_count[len] += 1;
				if (len != 0) {
					sorted_symbols.push({symbol: symbol, length: len});
				}
			}
			sorted_symbols.sortOn(["length", "symbol"], [Array.NUMERIC, Array.NUMERIC]);
			_max_length = length_count.length - 1;
			max_code = (1 << _max_length) - 1;
			
			// build the array out in order so that it's properly packed.
			// this is an AS3-specific optimization.
			_table = [];
			for (code = 0; code < (1 << _max_length); code++) {
				_table.push(null);
			}
			
			n = 0;
			code = 0;
			for (len = 1; len < length_count.length; len++) {
				k = (1 << len);
				if (!length_count[len]) length_count[len] = 0; // turns undefined into 0.
				for (i = 0; i < length_count[len]; i++) {
					set = [ sorted_symbols[n].symbol, len ];
					for (j = reverseBits(code, len); j <= max_code; j+= k) {
						_table[j] = set;
					}
					n++;
					code++;
				}
				code <<= 1;
			}
			
			/*
			trace("num codes: " + length);
			trace("max code length: " + _max_length);
			for (symbol = 0; symbol < length; symbol++) {
				trace("len[" + symbol + "] = " + code_lengths[symbol + offset]);
			}
			for (len = 0; len < length_count.length; len++) {
				trace("count[" + len + "] = " + length_count[len]);
			}
			*/
			
			DisposeUtil.genericDispose(sorted_symbols);
			DisposeUtil.genericDispose(length_count);
		}
		
		public function dispose():void
		{
			DisposeUtil.genericDispose(_table);
			_table = null;
		}
		
		private static function reverseBits(data:uint, numBits:uint):uint
		{
			var reversed:uint = 0;
			while (numBits) {
				reversed <<= 1;
				reversed |= data & 1;
				data >>= 1;
				numBits--;
			}
			return reversed;
		}
		
		public function get maxLength():uint
		{
			return _max_length;
		}
		
		public function bitsUsed(code:uint):uint
		{
			return _table[code][1];
		}
		
		public function decode(code:uint):uint
		{
			return _table[code][0];
		}
	}
}
