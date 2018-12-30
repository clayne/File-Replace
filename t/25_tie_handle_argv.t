#!/usr/bin/env perl
use warnings;
use strict;

=head1 Synopsis

Tests for the Perl module Tie::Handle::Argv.

=head1 Author, Copyright, and License

Copyright (c) 2018 Hauke Daempfling (haukex@zero-g.net)
at the Leibniz Institute of Freshwater Ecology and Inland Fisheries (IGB),
Berlin, Germany, L<http://www.igb-berlin.de/>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see L<http://www.gnu.org/licenses/>.

=cut

use FindBin ();
use lib $FindBin::Bin;
use File_Replace_Testlib;

use Test::More tests=>20;

use Cwd qw/getcwd/;
use File::Temp qw/tempdir/;

use warnings FATAL => qw/ io inplace /;
our $DEBUG = 0;
our $FE = $] lt '5.012' ? !!1 : !!0; # FE="first eof", see http://rt.perl.org/Public/Bug/Display.html?id=133721
our $BE; # BE="buggy eof", Perl 5.14.x had several regressions regarding eof (and a few others) (gets set below)
our $CE; # CE="can't eof()", Perl <5.12 doesn't support eof() on tied filehandles (gets set below)

BEGIN { use_ok('Tie::Handle::Argv') }

## no critic (RequireCarping)

sub testboth {  ## no critic (RequireArgUnpacking)
	# test that both regular ARGV and our tied base class act the same
	die "bad nr of args" unless @_==2 || @_==3;
	my ($name, $sub, $stdin) = @_;
	{
		local (*ARGV, $.);  ## no critic (RequireInitializationForLocalVars)
		my $osi = defined($stdin) ? OverrideStdin->new($stdin) : undef;
		subtest "$name - untied" => $sub;
		$osi and $osi->restore;
	}
	{
		local (*ARGV, $.);  ## no critic (RequireInitializationForLocalVars)
		local $CE = $] lt '5.012';
		local $BE = $] ge '5.014' && $] lt '5.016';
		tie *ARGV, 'Tie::Handle::Argv', debug=>$DEBUG;
		my $osi = defined($stdin) ? OverrideStdin->new($stdin) : undef;
		subtest "$name - tied" => $sub;
		$osi and $osi->restore;
		untie *ARGV;
	}
	return;
}

testboth 'basic test' => sub { plan tests=>1;
	my @tf = (newtempfn("Foo\nBar\n"), newtempfn("Quz\nBaz"));
	my @states;
	local @ARGV = @tf;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply \@states, [
		[[@tf],    undef,  !!0, undef, $FE         ],
		[[$tf[1]], $tf[0], !!1, 1,     !!0, "Foo\n"],
		[[$tf[1]], $tf[0], !!1, 2,     !!1, "Bar\n"],
		[[],       $tf[1], !!1, 3,     !!0, "Quz\n"],
		[[],       $tf[1], !!1, 4,     !!1, "Baz"  ],
		[[],       $tf[1], !!0, 4,     $BE?!!0:!!1 ],
	], 'states' or diag explain \@states;
};

testboth 'basic test with eof()' => sub {
	plan $CE ? ( skip_all=>"eof() not supported on tied handles on Perl<5.12" ) : (tests=>1); #TODO: do we need to be this drastic?
	my @tf = (newtempfn("Foo\nBar"), newtempfn("Quz\nBaz\n"));
	my @states;
	local @ARGV = @tf;
	# WARNING: eof() modifies $ARGV (and potentially others), so don't do e.g. [$ARGV, $., eof, eof()]!!
	# See e.g. https://www.perlmonks.org/?node_id=289044 and https://www.perlmonks.org/?node_id=1076954
	# and https://www.perlmonks.org/?node_id=1164369 and probably more
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof], eof();
	# eof() will open the first file, so record the current state again:
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof], eof();
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_], eof() while <>;
	# another call to eof() now would open and try to read STDIN (we test that in the STDIN tests)
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply \@states, [
		[[@tf],    undef,  !!0, undef,       $FE         ], !!0,
		[[$tf[1]], $tf[0], !!1, $BE?undef:0, !!0         ], !!0,
		[[$tf[1]], $tf[0], !!1, 1,           !!0, "Foo\n"], !!0,
		[[$tf[1]], $tf[0], !!1, 2,           !!1, "Bar"  ], !!0,
		[[],       $tf[1], !!1, 3,           !!0, "Quz\n"], !!0,
		[[],       $tf[1], !!1, 4,           !!1, "Baz\n"], !!1,
		[[],       $tf[1], !!0, 4,           $BE?!!0:!!1 ],
	], 'states' or diag explain \@states;
};

testboth 'readline contexts' => sub { plan tests=>2;
	# we test scalar everywhere, need to test the others too
	my @tf = (newtempfn("Alpha"), newtempfn("Bravo\nCharlie\nDelta"), newtempfn("Echo\n!!!"));
	my @states;
	local @ARGV = @tf;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	for (1..2) {
		<>; # void ctx
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	}
	my @got = <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply \@got, ["Charlie\n","Delta","Echo\n","!!!"], 'list ctx'
		or diag explain \@got;
	is_deeply \@states, [
		[[@tf],      undef,  !!0, undef, $FE        ],
		[[@tf[1,2]], $tf[0], !!1, 1,     !!1        ],
		[[$tf[2]],   $tf[1], !!1, 2,     !!0        ],
		[[],         $tf[2], !!0, 6,     $BE?!!0:!!1],
	], 'states' or diag explain \@states;
};

testboth 'restart argv' => sub { plan tests=>1;
	my $tfn = newtempfn("111\n222\n333\n");
	my @states;
	local @ARGV = ($tfn);
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	@ARGV = ($tfn);  ## no critic (RequireLocalizedPunctuationVars)
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply \@states, [
		[[$tfn], undef, !!0, undef, $FE         ],
		[[],     $tfn,  !!1, 1,     !!0, "111\n"],
		[[],     $tfn,  !!1, 2,     !!0, "222\n"],
		[[],     $tfn,  !!1, 3,     !!1, "333\n"],
		[[],     $tfn,  !!0, 3,     $BE?!!0:!!1 ],
		[[$tfn], $tfn,  !!0, 3,     $BE?!!0:!!1 ],
		[[],     $tfn,  !!1, 1,     !!0, "111\n"],
		[[],     $tfn,  !!1, 2,     !!0, "222\n"],
		[[],     $tfn,  !!1, 3,     !!1, "333\n"],
		[[],     $tfn,  !!0, 3,     $BE?!!0:!!1 ],
	], 'states' or diag explain \@states;
};

testboth 'close on eof to reset $.' => sub { plan tests=>1;
	my @tf = (newtempfn("One\nTwo\nThree\n"), newtempfn("Four\nFive\nSix"));
	my @states;
	local @ARGV = @tf;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	while (<>) {
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_];
	} continue {
		close ARGV if eof;
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	}
	@ARGV = ($tf[0]);  ## no critic (RequireLocalizedPunctuationVars)
	while (<>) {
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_];
	} continue {
		close ARGV if eof;
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	}
	is_deeply \@states, [
		[[@tf],    undef,  !!0, undef, $FE            ],
		[[$tf[1]], $tf[0], !!1, 1,     !!0, "One\n"   ],
		[[$tf[1]], $tf[0], !!1, 1,     !!0,           ],
		[[$tf[1]], $tf[0], !!1, 2,     !!0, "Two\n"   ],
		[[$tf[1]], $tf[0], !!1, 2,     !!0,           ],
		[[$tf[1]], $tf[0], !!1, 3,     !!1, "Three\n" ],
		[[$tf[1]], $tf[0], !!0, 0,     !!1,           ],
		[[],       $tf[1], !!1, 1,     !!0, "Four\n"  ],
		[[],       $tf[1], !!1, 1,     !!0,           ],
		[[],       $tf[1], !!1, 2,     !!0, "Five\n"  ],
		[[],       $tf[1], !!1, 2,     !!0,           ],
		[[],       $tf[1], !!1, 3,     !!1, "Six"     ],
		[[],       $tf[1], !!0, 0,     !!1,           ],
		[[],       $tf[0], !!1, 1,     !!0, "One\n"   ],
		[[],       $tf[0], !!1, 1,     !!0,           ],
		[[],       $tf[0], !!1, 2,     !!0, "Two\n"   ],
		[[],       $tf[0], !!1, 2,     !!0,           ],
		[[],       $tf[0], !!1, 3,     !!1, "Three\n" ],
		[[],       $tf[0], !!0, 0,     !!1,           ],
	], 'states' or diag explain \@states;
};

=begin comment

#TODO Later: I can't run both STDIN tests in one file, not sure why yet

testboth 'initially empty @ARGV' => sub { plan tests=>1;
	my @states;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply \@states, [
		[[], undef, !!0, undef, $FE          ],
		[[], '-',   !!1, 1,     !!0, "BlaH\n"],
		[[], '-',   !!1, 2,     !!1, "BlaHHH"],
		[[], '-',   !!0, 2,     !!1          ],
	], 'states' or diag explain \@states;
}, "BlaH\nBlaHHH";

=end comment

=cut

testboth 'restart with emptied @ARGV' => sub { plan tests=>2;
	my @tf = (newtempfn("Fo\nBr"), newtempfn("Qz\nBz\n"));
	my @states;
	local @ARGV = @tf;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	#TODO Later: probably need to skip the following eof() test on Perls <5.12
	ok !eof(), 'eof() is false';
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply \@states, [
		[[@tf],    undef,  !!0, undef, $FE           ],
		[[$tf[1]], $tf[0], !!1, 1,     !!0, "Fo\n"   ],
		[[$tf[1]], $tf[0], !!1, 2,     !!1, "Br"     ],
		[[],       $tf[1], !!1, 3,     !!0, "Qz\n"   ],
		[[],       $tf[1], !!1, 4,     !!1, "Bz\n"   ],
		[[],       $tf[1], !!0, 4,     $BE?!!0:!!1   ],
		[[],       '-',    !!1, 0,     !!0           ],
		[[],       '-',    !!1, 1,     !!0, "Hello\n"],
		[[],       '-',    !!1, 2,     !!1, "World"  ],
		[[],       '-',    !!0, 2,     $BE?!!0:!!1   ],
	], 'states' or diag explain \@states;
}, "Hello\nWorld";

testboth 'nonexistent and empty files' => sub { plan tests=>7;
	my @tf = (newtempfn(""), newtempfn("Hullo"), newtempfn, newtempfn(""), newtempfn, newtempfn("World!\nFoo!"), newtempfn(""));
	ok !-e $tf[$_], "file $_ doesn't exist" for 2,4;
	my @states;
	local @ARGV = @tf;
	use warnings NONFATAL => 'inplace';
	my $warncount;
	local $SIG{__WARN__} = sub {
		if ( $_[0]=~/\bCan't open (?:\Q$tf[2]\E|\Q$tf[4]\E): / )
			{ $warncount++ }
		else { die @_ } };
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	@ARGV = @tf;  ## no critic (RequireLocalizedPunctuationVars)
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply [<>], ["Hullo","World!\n","Foo!"], '<> in list ctx';
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	ok !-e $tf[$_], "file $_ doesn't exist" for 2,4;
	is_deeply \@states, [
		[[@tf],       undef,  !!0, undef, $FE            ],
		[[@tf[2..6]], $tf[1], !!1, 1,     !!1, "Hullo"   ],
		[[$tf[6]],    $tf[5], !!1, 2,     !!0, "World!\n"],
		[[$tf[6]],    $tf[5], !!1, 3,     !!1, "Foo!"    ],
		[[],          $tf[6], !!0, 3,     $BE?!!0:!!1    ],
		[[@tf],       $tf[6], !!0, 3,     $BE?!!0:!!1    ],
		[[],          $tf[6], !!0, 3,     $BE?!!0:!!1    ],
	], 'states' or diag explain \@states;
	is $warncount, 4, 'warning count';
};

testboth 'premature close' => sub { plan tests=>1;
	my @tf = (newtempfn("Foo\nBar\n"), newtempfn("Quz\nBaz"));
	my @states;
	local @ARGV = @tf;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	my $l=<>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $l];
	close ARGV;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
	push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
	is_deeply \@states, [
		[[@tf],    undef,  !!0, undef, $FE         ],
		[[$tf[1]], $tf[0], !!1, 1,     !!0, "Foo\n"],
		[[$tf[1]], $tf[0], !!0, 0,     !!1         ],
		[[],       $tf[1], !!1, 1,     !!0, "Quz\n"],
		[[],       $tf[1], !!1, 2,     !!1, "Baz"  ],
		[[],       $tf[1], !!0, 2,     $BE?!!0:!!1 ],
	], 'states' or diag explain \@states;
};

subtest 'special filenames and double-diamond' => sub { plan tests=>2*2;
	my $prevdir = getcwd;
	my $tmpdir = tempdir(DIR=>$TEMPDIR,CLEANUP=>1);
	chdir($tmpdir) or die "chdir $tmpdir: $!";
	# this should also apply to piped opens etc.
	spew("foo","not\nspecial");
	spew("<foo","Special!\nFilename!");
	testboth 'diamond' => sub { plan tests=>1;
		my @states;
		local @ARGV = ("<foo");
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <>;
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
		is_deeply \@states, [
			[["<foo"], undef,  !!0, undef, $FE           ],
			[[],       "<foo", !!1, 1,     !!0, "not\n"  ],
			[[],       "<foo", !!1, 2,     !!1, "special"],
			[[],       "<foo", !!0, 2,     $BE?!!0:!!1   ],
		], 'states' or diag explain \@states;
	};
	testboth 'double-diamond' => sub {
		plan $] lt '5.022' ? (skip_all => 'need Perl >=5.22 for double-diamond') : (tests=>1);
		my @states;
		local @ARGV = ("<foo");
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
		my $code = <<'        ENDCODE';  # need to eval this because otherwise <<>> is a syntax error on older Perls
			push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof, $_] while <<>>;
		; 1
        ENDCODE
		eval $code or die $@||"unknown error";  ## no critic (ProhibitStringyEval, ProhibitMixedBooleanOperators)
		push @states, [[@ARGV], $ARGV, defined(fileno ARGV), $., eof];
		TODO: { local $TODO; tied(*ARGV) and $TODO =  ## no critic (RequireInitializationForLocalVars)
				"double-diamond not yet supported with tied filehandles (?)";
			is_deeply \@states, [
				[["<foo"], undef,  !!0, undef, $FE              ],
				[[],       "<foo", !!1, 1,     !!0, "Special!\n"],
				[[],       "<foo", !!1, 2,     !!1, "Filename!" ],
				[[],       "<foo", !!0, 2,     !!1              ],
			], 'states for double-diamond';
		}
	};
	chdir($prevdir) or warn "chdir $prevdir: $!";
};

subtest 'debugging (and coverage)' => sub { plan tests=>4;
	local (*ARGV, $.);  ## no critic (RequireInitializationForLocalVars)
	note "Expect some debug output here:";
	@ARGV = (newtempfn("One\nTwo"));  ## no critic (RequireLocalizedPunctuationVars)
	my $db = Test::More->builder->output;
	tie *ARGV, 'Tie::Handle::Argv', debug=>$db;
	is scalar <>, "One\n", 'debug w/ handle';
	untie *ARGV;
	@ARGV = (newtempfn("Three"));  ## no critic (RequireLocalizedPunctuationVars)
	local *STDERR = $db;
	tie *ARGV, 'Tie::Handle::Argv', debug=>1;
	# for code coverage of the (unlikely) condition that eof was
	# false but readline still returns undef:
	open my $sfh, '<', \(my $somestr = "") or die $!;  ## no critic (RequireBriefOpen)
	tied(*ARGV)->set_inner_handle(Tie::Handle::NeverEof->new($sfh));
	ok !tied(*ARGV)->EOF(), 'eof is false';
	is scalar <>, undef, 'debug w/o handle';
	like exception { tied(*ARGV)->_debug() },
		qr/\bnot enough arguments\b/, '_debug not enough args';
	untie *ARGV;
};

subtest 'misc errors' => sub { plan tests=>5;
	local (*ARGV, $.);  ## no critic (RequireInitializationForLocalVars)
	like exception {
			tie *ARGV, 'Tie::Handle::Argv', "foo";
		}, qr/\bbad number of arguments\b/, 'tiehandle bad nr of args';
	like exception {
			tie *ARGV, 'Tie::Handle::Argv', foo => "bar";
		}, qr/\bunknown argument 'foo'/, 'tiehandle bad arg';
	tie *ARGV, 'Tie::Handle::Argv', debug=>$DEBUG;
	like exception { tied(*ARGV)->_close() },
		qr/\bbad number of arguments\b/, '_close bad nr of args';
	like exception { print ARGV "something" },
		qr/\bis read-only\b/, 'argv read-only';
	like exception { tied(*ARGV)->_advance(1,2) },
		qr/\btoo many arguments\b/, '_advance too many args';
	untie *ARGV;
};

