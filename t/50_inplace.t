#!/usr/bin/env perl
use warnings;
use strict;

=head1 Synopsis

Tests for the Perl module File::Replace::Inplace.

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

use Test::More tests=>18;

use Cwd qw/getcwd/;
use File::Temp qw/tempdir/;
use File::Spec::Functions qw/catdir catfile/;
use IPC::Run3::Shell 0.56 ':FATAL', [ perl => { fail_on_stderr=>1,
	show_cmd=>Test::More->builder->output },
	$^X, '-wMstrict', '-I'.catdir($FindBin::Bin,'..','lib') ];

# Note: At the very first call to "eof", the "most recent filehandle" won't be ARGV.
my $FE = $] lt '5.012' ? !!1 : !!0; # FE="first eof", see http://rt.perl.org/Public/Bug/Display.html?id=133721

## no critic (RequireCarping)

BEGIN {
	use_ok 'File::Replace::Inplace';
	use_ok 'File::Replace', 'inplace';
}
use warnings FATAL => 'File::Replace';

subtest 'basic test' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my @tf = (newtempfn("Foo\nBar"), newtempfn("Quz\nBaz\n"));
	local @ARGV = @tf;
	my @states;
	{
		my $inpl = File::Replace::Inplace->new();
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		ok !defined(fileno ARGV), 'ARGV closed initially';
		ok !defined(fileno ARGVOUT), 'ARGVOUT closed initially';
		push @states, [$ARGV, $., eof], eof();
		#TODO: does/should eof() open ARGV for tied handles too?
		#ok  defined(fileno ARGV), 'ARGV open'; # opened by eof()
		#ok  defined(fileno ARGVOUT), 'ARGVOUT open'; # opened by eof()
		while (<>) {
			print "$ARGV:$.: ".uc;
			ok  defined(fileno ARGV), 'ARGV still open';
			ok  defined(fileno ARGVOUT), 'ARGVOUT still open';
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		ok !defined(fileno ARGV), 'ARGV closed again';
		ok !defined(fileno ARGVOUT), 'ARGVOUT closed again';
		push @states, [$ARGV, $., eof]; # another call to eof() would open and try to read STDIN
	}
	is @ARGV, 0, '@ARGV empty';
	is slurp($tf[0]), "$tf[0]:1: FOO\n$tf[0]:2: BAR", 'file 1 contents';
	is slurp($tf[1]), "$tf[1]:3: QUZ\n$tf[1]:4: BAZ\n", 'file 2 contents';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,    [$tf[0], 1, !!0], !!0,
		[$tf[0], 2, !!1], !!0,       [$tf[1], 3, !!0], !!0,
		[$tf[1], 4, !!1], !!1,       [$tf[1], 4, !!1],
	], 'states' or diag explain \@states;
};

subtest 'inplace()' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my @tf = (newtempfn("X\nY\nZ"), newtempfn("AA\nBB\nCC\n"));
	my @files = @tf;
	local @ARGV = ('foo','bar');
	my @states;
	{
		my $inpl = inplace( files=>\@files );
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		push @states, [$ARGV, $., eof], eof();
		while (<>) {
			print "$ARGV:$.: ".uc;
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		push @states, [$ARGV, $., eof];
	}
	is_deeply \@ARGV, ['foo','bar'], '@ARGV unaffected';
	is @files, 0, '@files was emptied';
	is slurp($tf[0]), "$tf[0]:1:X\n$tf[0]:2:Y\n$tf[0]:3:Z", 'file 1 contents';
	is slurp($tf[1]), "$tf[1]:4:AA\n$tf[1]:5:BB\n$tf[1]:6:CC\n", 'file 2 contents';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,    [$tf[0], 1, !!0], !!0,
		[$tf[0], 2, !!0], !!0,       [$tf[0], 3, !!1], !!0,
		[$tf[1], 4, !!0], !!0,       [$tf[1], 5, !!0], !!0,
		[$tf[1], 6, !!1], !!1,       [$tf[1], 6, !!1],
	], 'states' or diag explain \@states;
};

subtest 'backup' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my $tfn = newtempfn("Foo\nBar");
	my $bfn = $tfn.'.bak';
	{
		ok !-e $bfn, 'backup file doesn\'t exist yet';
		my $inpl = File::Replace::Inplace->new( files=>[$tfn], backup=>'.bak' );
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		is eof, $FE, 'eof before';
		is eof(), !!0, 'eof() before';
		print "$ARGV+$.+$_" while <>;
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		is eof, !!1, 'eof after';
	}
	is $., 2, '$. correct';
	is slurp($tfn), "$tfn+1+Foo\n$tfn+2+Bar", 'file edited correctly';
	is slurp($bfn), "Foo\nBar", 'backup file correct';
};

subtest 'cmdline' => sub {
	my @tf = (newtempfn("One\nTwo\n"), newtempfn("Three\nFour"));
	is perl('-MFile::Replace=-i','-pe','s/[aeiou]/_/gi', @tf), '', 'no output';
	is slurp($tf[0]), "_n_\nTw_\n", 'file 1 correct';
	is slurp($tf[1]), "Thr__\nF__r", 'file 2 correct';
	my @bf = map { "$_.bak" } @tf;
	ok !-e $bf[0], 'backup 1 doesn\'t exist';
	ok !-e $bf[1], 'backup 2 doesn\'t exist';
	is perl('-MFile::Replace=-i.bak','-nle','print "$ARGV:$.: $_"', @tf), '', 'no output (2)';
	is slurp($tf[0]), "$tf[0]:1: _n_\n$tf[0]:2: Tw_\n", 'file 1 correct (2)';
	is slurp($tf[1]), "$tf[1]:3: Thr__\n$tf[1]:4: F__r\n", 'file 2 correct (2)';
	is slurp($bf[0]), "_n_\nTw_\n", 'backup file 1 correct';
	is slurp($bf[1]), "Thr__\nF__r", 'backup file 2 correct';
};

subtest '-i in import list' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my @tf = (newtempfn("XX\nYY\n"), newtempfn("ABC\nDEF\nGHI"));
	local @ARGV = @tf;
	ok !defined $File::Replace::GlobalInplace, 'GlobalInplace not set yet';
	File::Replace->import('-i');
	ok  defined $File::Replace::GlobalInplace, 'GlobalInplace is now set';
	while (<>) {
		print "$ARGV:$.:".lc;
	}
	is slurp($tf[0]), "$tf[0]:1:xx\n$tf[0]:2:yy\n", 'file 1 correct';
	is slurp($tf[1]), "$tf[1]:3:abc\n$tf[1]:4:def\n$tf[1]:5:ghi", 'file 2 correct';
	$File::Replace::GlobalInplace = undef;  ## no critic (ProhibitPackageVars)
	is @ARGV, 0, '@ARGV empty';
	# a couple more checks for code coverage
	File::Replace->import('-D');
	is undef, $File::Replace::GlobalInplace, 'lone debug flag has no effect';  ## no critic (ProhibitPackageVars)
	like exception {File::Replace->import('-i','-D','-i.bak')},
		qr/\bmore than one -i\b/, 'multiple -i\'s fails';
	$File::Replace::GlobalInplace = undef;  ## no critic (ProhibitPackageVars)
};

subtest 'cleanup' => sub { # mostly just to make code coverage happy
	my $tmpfile = newtempfn("Yay\nHooray");
	{
		my $inpl = inplace( files=>[$tmpfile] );
		print "<$.>$_" while <>;
		$inpl->cleanup;
		tie *ARGV, 'Tie::Handle::Base'; # cleanup should only untie if tied to File::Replace::Inplace
		$inpl->cleanup;
		untie *ARGV;
	}
	is slurp($tmpfile), "<1>Yay\n<2>Hooray", 'file correct';
};

subtest 'readline contexts' => sub { # we test scalar everywhere, need to test the others too
	local (*ARGV, *ARGVOUT, $.);
	my @tf = (newtempfn("So"), newtempfn("Many\nTests\nis"), newtempfn("fun\n!!!"));
	my @states;
	{
		my $inpl = inplace( files=>[@tf] );
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		push @states, [$ARGV, $., eof], eof();
		# at the moment, void context is handled the same as scalar, but test it anyway
		for (1..2) {
			push @states, [$ARGV, $., eof], eof();
			<>;
			push @states, [$ARGV, $., eof], eof();
		}
		print "Hi?\n";
		my @got = <>;
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		push @states, [$ARGV, $., eof];
		is_deeply \@got, ["Tests\n","is","fun\n","!!!"], 'list ctx' or diag explain \@got;
	}
	is slurp($tf[0]), "", 'file 1 correct';
	is slurp($tf[1]), "Hi?\n", 'file 2 correct';
	is slurp($tf[2]), "", 'file 3 correct';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,    [$tf[0], 0, !!0], !!0,
		[$tf[0], 1, !!1], !!0,       [$tf[1], 1, !!0], !!0,
		[$tf[1], 2, !!0], !!0,       [$tf[2], 6, !!1],
	], 'states' or diag explain \@states;
};

subtest 'restart' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my $tfn = newtempfn("111\n222\n333\n");
	local @ARGV = ($tfn);
	my @states;
	{
		my $inpl = File::Replace::Inplace->new();
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		push @states, [$ARGV, $., eof], eof();
		while (<>) {
			print "X/$.:$_";
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected in between';
		@ARGV = ($tfn);  ## no critic (RequireLocalizedPunctuationVars)
		while (<>) {
			print "Y/$.:$_";
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		push @states, [$ARGV, $., eof];
	}
	is slurp($tfn), "Y/1:X/1:111\nY/2:X/2:222\nY/3:X/3:333\n", 'file correct';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,    [$tfn, 1, !!0], !!0,
		[$tfn, 2, !!0], !!0,         [$tfn, 3, !!1], !!1,
		[$tfn, 1, !!0], !!0,         [$tfn, 2, !!0], !!0,
		[$tfn, 3, !!1], !!1,         [$tfn, 3, !!1],
	], 'states' or diag explain \@states;
};

subtest 'reset $. on eof' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my @tf = (newtempfn("One\nTwo\nThree\n"), newtempfn("Four\nFive\nSix"));
	local @ARGV = @tf;
	my @states;
	{
		my $inpl = File::Replace::Inplace->new();
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		push @states, [$ARGV, $., eof], eof();
		#TODO: Can we use our overridden eof() here?
		while (<>) {
			print "($.)$_";
			push @states, [$ARGV, $., eof];
		}
		# as documented in eof, this should reset $. per file
		continue {
			close ARGV if eof;
			push @states, [$ARGV, $., eof];
		}
		@ARGV = ($tf[0]);  ## no critic (RequireLocalizedPunctuationVars)
		while (<>) {
			print "[$.]$_";
			push @states, [$ARGV, $., eof];
		}
		continue {
			close ARGV if eof;
			push @states, [$ARGV, $., eof];
		}
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		push @states, [$ARGV, $., eof];
	}
	is slurp($tf[0]), "[1](1)One\n[2](2)Two\n[3](3)Three\n", 'file 1 correct';
	is slurp($tf[1]), "(1)Four\n(2)Five\n(3)Six", 'file 2 correct';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,
		[$tf[0], 1, !!0],    [$tf[0], 1, !!0],
		[$tf[0], 2, !!0],    [$tf[0], 2, !!0],
		[$tf[0], 3, !!1],    [$tf[0], 0, !!1],
		[$tf[1], 1, !!0],    [$tf[1], 1, !!0],
		[$tf[1], 2, !!0],    [$tf[1], 2, !!0],
		[$tf[1], 3, !!1],    [$tf[1], 0, !!1],
		[$tf[0], 1, !!0],    [$tf[0], 1, !!0],
		[$tf[0], 2, !!0],    [$tf[0], 2, !!0],
		[$tf[0], 3, !!1],    [$tf[0], 0, !!1],
		[$tf[0], 0, !!1],
	], 'states' or diag explain \@states;
};

subtest 'restart with emptied @ARGV' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my @tf = (newtempfn("Foo\nBar"), newtempfn("Quz\nBaz\n"));
	my @out;
	my @states;
	{
		my $stdin = OverrideStdin->new("Hello\nWorld");
		my $inpl = File::Replace::Inplace->new( files=>[@tf] );
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		push @states, [$ARGV, $., eof], eof();
		while (<>) {
			print "$ARGV:$.: ".uc;
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected in between';
		while (<>) {
			push @out, "2/$ARGV:$.: ".uc;
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		push @states, [$ARGV, $., eof];
	}
	is_deeply \@out, ["2/-:1: HELLO\n", "2/-:2: WORLD"], 'stdin/out looks ok';
	is slurp($tf[0]), "$tf[0]:1: FOO\n$tf[0]:2: BAR", 'file 1 correct';
	is slurp($tf[1]), "$tf[1]:3: QUZ\n$tf[1]:4: BAZ\n", 'file 2 correct';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,    [$tf[0], 1, !!0], !!0,
		[$tf[0], 2, !!1], !!0,       [$tf[1], 3, !!0], !!0,
		[$tf[1], 4, !!1], !!1,       ['-',    1, !!0], !!0,
		['-',    2, !!1], !!1,       ['-',    2, !!1],
	], 'states' or diag explain \@states;
};

subtest 'initially empty @ARGV' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my @out;
	my @states;
	{
		my $stdin = OverrideStdin->new("BlaH\nBlaHHH");
		my $inpl = File::Replace::Inplace->new();
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		push @states, [$ARGV, $., eof], eof();
		while (<>) {
			push @out, "+$ARGV:$.:".lc;
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		push @states, [$ARGV, $., eof];
	}
	is_deeply \@out, ["+-:1:blah\n", "+-:2:blahhh"], 'stdin/out looks ok';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,    ['-', 1, !!0], !!0,
		['-', 2, !!1], !!1,          ['-', 2, !!1],
	], 'states' or diag explain \@states;
};

subtest 'nonexistent files' => sub {
	my @tf;
	my %codes = (
		scalar => sub {
			my $inpl = File::Replace::Inplace->new( files=>[@tf] );
			is_deeply [$ARGV, $., eof], [undef, undef, $FE], 'state 1';
			is eof(), !!0, 'eof() 1';
			is <>, 'Hullo', 'read 1';
			print "World\n";
			is_deeply [$ARGV, $., eof], [$tf[2], 1, !!1], 'state 2';
			is eof(), !!1, 'eof() 2';
			is <>, undef, 'read 2';
			is_deeply [$ARGV, $., eof], [$tf[2], 1, !!1], 'state 3';
		},
		list => sub {
			my $inpl = File::Replace::Inplace->new( files=>[@tf] );
			is_deeply [$ARGV, $., eof], [undef, undef, $FE], 'state 1';
			is eof(), !!0, 'eof() before';
			is_deeply [<>], ["Hullo"], 'readline return correct';
			is_deeply [$ARGV, $., eof], [$tf[2], 1, !!1], 'state 2';
		},
	);
	plan tests => scalar keys %codes;
	for my $k (sort keys %codes) {
		subtest $k => sub {
			local (*ARGV, *ARGVOUT, $.);
			@tf = (newtempfn, newtempfn, newtempfn("Hullo"));
			ok !-e $tf[0], 'file 1 doesn\'t exist yet';
			ok !-e $tf[1], 'file 2 doesn\'t exist yet';
			ok -e $tf[2], 'file 3 already exists';
			is select(), 'main::STDOUT', 'STDOUT is selected initially';
			$codes{$k}->();
			is select(), 'main::STDOUT', 'STDOUT is selected again';
			# NOTE: difference to Perl's -i - File::Replace will create the files
			ok -e $tf[0], 'file 1 now exists';
			ok -e $tf[1], 'file 2 now exists';
			is slurp($tf[0]), '', 'file 1 is empty';
			is slurp($tf[1]), '', 'file 2 is empty';
			is slurp($tf[2]), $k eq 'scalar' ? "World\n" : "", 'file 3 contents ok';
		};
	}
};

subtest 'empty files' => sub {
	local (*ARGV, *ARGVOUT, $.);
	my @tf = (newtempfn(""), newtempfn("Hello"), newtempfn(""), newtempfn, newtempfn("World!\nFoo!"));
	local @ARGV = @tf;
	my @states;
	{
		my $inpl = File::Replace::Inplace->new();
		is select(), 'main::STDOUT', 'STDOUT is selected initially';
		push @states, [$ARGV, $., eof], eof();
		while (<>) {
			print "$ARGV($.) ".uc;
			push @states, [$ARGV, $., eof], eof();
		}
		is select(), 'main::STDOUT', 'STDOUT is selected again';
		push @states, [$ARGV, $., eof];
	}
	is @ARGV, 0, '@ARGV empty';
	is slurp($tf[0]), "", 'file 1 contents';
	is slurp($tf[1]), "$tf[1](1) HELLO", 'file 2 contents';
	is slurp($tf[2]), "", 'file 3 contents';
	ok !-e $tf[3], 'file 4 doesn\'t exist';
	is slurp($tf[4]), "$tf[4](2) WORLD!\n$tf[4](3) FOO!", 'file 5 contents';
	is_deeply \@states, [
		[undef, undef, $FE], !!0,    [$tf[1], 1, !!1], !!0,
		[$tf[4], 2, !!0], !!0,       [$tf[4], 3, !!1], !!1,
		[$tf[4], 3, !!1],
	], 'states' or diag explain \@states;
};

subtest 'various file names' => sub {
	my $prevdir = getcwd;
	my $tmpdir = tempdir(DIR=>$TEMPDIR,CLEANUP=>1);
	chdir($tmpdir) or die "chdir $tmpdir: $!";
	spew("-","sttdddiiiinnnnn hello\nxyz\n");
	spew("echo|","piipppeee world\naa bb cc");
	local @ARGV = ("-","echo|");
	{
		my $inpl = inplace();
		while (<>) {
			chomp;
			print join(",", map {ucfirst} split), "\n";
		}
	}
	is slurp("-"), "Sttdddiiiinnnnn,Hello\nXyz\n", 'file 1 correct';
	is slurp("echo|"), "Piipppeee,World\nAa,Bb,Cc\n", 'file 2 correct';
	chdir($prevdir) or warn "chdir $prevdir: $!";
};

subtest 'debug' => sub {
	note "Expect some debug output here:";
	my $db = Test::More->builder->output;
	ok( do { my $x=File::Replace::Inplace->new(debug=>$db); 1 }, 'debug w/ handle' );
	local *STDERR = $db;
	ok( do { my $x=File::Replace::Inplace->new(debug=>1); 1 }, 'debug w/o handle' );
};

subtest 'misc failures' => sub {
	like exception { inplace(); 1 },
		qr/\bUseless use of .*->new in void context\b/, 'inplace in void ctx';
	like exception { my $x=inplace('foo') },
		qr/\bnew: bad number of args\b/, 'bad nr of args 1';
	like exception { File::Replace::Inplace::TiedArgv::TIEHANDLE() },
		qr/\bTIEHANDLE: bad number of args\b/, 'bad nr of args 2';
	like exception { File::Replace::Inplace::TiedArgv::TIEHANDLE('x','y') },
		qr/\bTIEHANDLE: bad number of args\b/, 'bad nr of args 3';
	like exception { my $x=inplace(badarg=>1) },
		qr/\bunknown option\b/, 'unknown arg';
	like exception { my $x=inplace(files=>"foo") },
		qr/\bmust be an arrayref\b/, 'bad file arg';
	like exception {
			my $i = inplace();
			open ARGV, '<', newtempfn or die $!;  ## no critic (ProhibitBarewordFileHandles)
			close ARGV;
		}, qr/\bCan't reopen ARGV while tied\b/i, 'reopen ARGV';
};

