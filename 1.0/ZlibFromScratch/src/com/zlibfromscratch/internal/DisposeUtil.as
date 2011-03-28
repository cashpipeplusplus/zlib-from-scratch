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
	public class DisposeUtil
	{
		public static function genericDispose(x:*):void
		{
			if (x is Array) {
				for (var i:int = x.length - 1; i >= 0; i--) {
					genericDispose(x[i]);
					x.splice(i, 1);
				}
			} else if (x is String) {
				// do nothing, just don't treat it as an Object.
			} else if (x is Object) {
				for (var k:String in x) {
					genericDispose(x[k]);
					delete x[k];
				}
			}
		}
	}
}
