#!/usr/bin/perl

# This file is a part of ZlibFromScratch,
# an open-source ActionScript decompression library.
# Copyright (C) 2011 - Joey Parrish
# 
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
# 
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public
# License along with this library.
# If not, see <http://www.gnu.org/licenses/>.


# This script generates the lookup tables that will be embedded in the decoder.


use strict;

sub run_codes($$$$$)
{
	my ($description, $name, $i, $j) = @_;

	my ($f1, $f2);
	open($f1, ">$name.extra_bits") || die;
	open($f2, ">$name.base_values") || die;
	binmode($f1);
	binmode($f2);

	foreach my $d (@$description) {
		for (; $i < $d->[0]; $i++) {
			my ($v1, $v2);
			if ($d->[1]) {
				$v1 = 0;
				$v2 = 0;
			} else {
				$v1 = $d->[2];
				$v2 = $j + $d->[3];
				$j += (1 << $d->[2]);
			}

			syswrite($f1, pack("C", $v1), 1);
			syswrite($f2, pack("n", $v2), 2);
		}
	}

	close($f1);
	close($f2);
}

my $d;

$d = [
	# limit, zeroed, bits, adj
	[ 257,   1 ],
	[ 265,   0,      0   ,  0 ],
	[ 269,   0,      1   ,  0 ],
	[ 273,   0,      2   ,  0 ],
	[ 277,   0,      3   ,  0 ],
	[ 281,   0,      4   ,  0 ],
	[ 285,   0,      5   ,  0 ],
	[ 286,   0,      0   , -1 ],
];
&run_codes($d, "lcodes", 0, 3);

$d = [
	# limit, zeroed, bits, adj
	[  4,    0,       0  ,  0 ],
	[  6,    0,       1  ,  0 ],
	[  8,    0,       2  ,  0 ],
	[ 10,    0,       3  ,  0 ],
	[ 12,    0,       4  ,  0 ],
	[ 14,    0,       5  ,  0 ],
	[ 16,    0,       6  ,  0 ],
	[ 18,    0,       7  ,  0 ],
	[ 20,    0,       8  ,  0 ],
	[ 22,    0,       9  ,  0 ],
	[ 24,    0,      10  ,  0 ],
	[ 26,    0,      11  ,  0 ],
	[ 28,    0,      12  ,  0 ],
	[ 30,    0,      13  ,  0 ],
];
&run_codes($d, "dcodes", 0, 1);

sub run_array($$$$)
{
	my ($name, $pack_spec, $bytes, $array) = @_;

	my $f1;
	open($f1, ">$name") || die;
	binmode($f1);

	foreach my $x (@$array) {
		syswrite($f1, pack($pack_spec, $x), $bytes);
	}

	close($f1);
}

&run_array("deflate_length_mix", "C", 1, [ 3, 17, 15, 13, 11, 9, 7, 5, 4, 6, 8, 10, 12, 14, 16, 18, 0, 1, 2 ]);
&run_array("deflate_length_unmix", "C", 1, [ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 ]);

sub run_lengths($$)
{
	my ($name, $d) = @_;

	my $f1;
	open($f1, ">$name") || die;
	binmode($f1);

	my $i;
	for (my $i = 0; $i < scalar(@$d) - 1; $i++) {
		for (my $j = $d->[$i]->[0]; $j < $d->[$i + 1]->[0]; $j++) {
			syswrite($f1, pack("C", $d->[$i]->[1]), 1);
		}
	}

	close($f1);
}

$d = [ [ 0, 8 ], [ 144, 9 ], [ 256, 7 ], [ 280, 8 ], [ 288, -1 ] ];
&run_lengths("deflate_fixed_lengths", $d);

