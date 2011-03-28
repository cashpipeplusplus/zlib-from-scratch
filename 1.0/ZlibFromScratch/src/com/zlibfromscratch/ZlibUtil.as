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
	import flash.utils.ByteArray;
	
	/** Utility functions for use with <code>ZlibDecoder</code>. */
	public class ZlibUtil
	{
		/**
		 * Removes <code>numBytes</code> bytes from the beginning of
		 * <code>data</code> in the most efficient way possible.
		 * 
		 * @param data The data to truncate.
		 * @param numBytes The number of bytes to remove.
		 * 
		 * @return The altered <code>ByteArray</code>.
		 *   This may or may not be the same object as <code>data</code>.
		 * 
		 * @example The correct usage is always to set <code>data</code> with the return value:
		 * 
		 * <listing version="3.0">data = ZlibUtil.removeBeginning(data, numBytes);</listing>
		 */
		public static function removeBeginning(data:ByteArray, numBytes:uint):ByteArray
		{
			if (numBytes == 0) {
				return data;
			}
			
			if (numBytes == data.length) {
				data.clear();
				return data;
			}
			
			var leftOvers:ByteArray = new ByteArray;
			leftOvers.writeBytes(data, numBytes);
			data.clear();
			return leftOvers;
		}
	}
}
