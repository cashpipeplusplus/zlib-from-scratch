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
	import flash.utils.ByteArray;
	
	/** @private For internal use only. */
	public class CRC32 implements IChecksum
	{
		private static var _table:Array;
		private var _acc:uint;
		private var _bytes:uint;
		
		public function CRC32()
		{
			if (!_table) {
				var c:uint, n:uint, k:uint;
				_table = [];
				for (n = 0; n < 256; n++) {
					c = n;
					for (k = 0; k < 8; k++) {
						if (c & 1) {
							c = 0xedb88320 ^ ((c >> 1) & 0x7fffffff);
						} else {
							c = (c >> 1) & 0x7fffffff;
						}
					}
					_table[n] = c;
				}
			}
			
			_acc = ~0;
			_bytes = 0;
		}
		
		public function feed(input:ByteArray, position:uint, length:uint):void
		{
			for (var i:uint = position; i < position + length; i++) {
				var x:uint = (_acc ^ input[i]) & 0xff;
				_acc = _table[x] ^ ((_acc >> 8) & 0x00ffffff);
			}
			_bytes += length;
		}
		
		public function feedByte(byte:uint):void
		{
			var x:uint = (_acc ^ byte) & 0xff;
			_acc = _table[x] ^ ((_acc >> 8) & 0x00ffffff);
			_bytes++;
		}
		
		public function get checksum():uint
		{
			return ~_acc;
		}
		
		public function get bytesAccumulated():uint
		{
			return _bytes;
		}
	}
}
