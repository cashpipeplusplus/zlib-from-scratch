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
	public class Adler32 implements IChecksum
	{
		private static const BLOCK_SIZE:uint = 5552;
		private static const MODULO:uint = 65521;
		
		private var s1:uint;
		private var s2:uint;
		private var bytesLeftInBlock:uint;
		
		public function Adler32()
		{
			s1 = 1;
			s2 = 0;
			bytesLeftInBlock = BLOCK_SIZE;
		}
		
		public function feed(input:ByteArray, position:uint, length:uint):void
		{
			for (var i:uint = position; i < position + length; i++) {
				s1 += input[i];
				s2 += s1;
				bytesLeftInBlock--;
				if (bytesLeftInBlock == 0) {
					s1 %= MODULO;
					s2 %= MODULO;
					bytesLeftInBlock = BLOCK_SIZE;
				}
			}
		}
		
		public function feedByte(byte:uint):void
		{
			s1 += byte;
			s2 += s1;
			bytesLeftInBlock--;
			if (bytesLeftInBlock == 0) {
				s1 %= MODULO;
				s2 %= MODULO;
				bytesLeftInBlock = BLOCK_SIZE;
			}
		}
		
		public function get checksum():uint
		{
			var tmp1:uint = s1 % MODULO;
			var tmp2:uint = s2 % MODULO;
			var sum:uint = (tmp2 << 16) | tmp1;
			return sum;
		}
		
		public function get bytesAccumulated():uint
		{
			// not supported.
			return 0;
		}
	}
}
