#!/usr/bin/env perl
use warnings FATAL=>'all';
use strict;

=head1 Synopsis

Tests for the Perl module File::Replace.

=head1 Author, Copyright, and License

Copyright (c) 2017-2023 Hauke Daempfling (haukex@zero-g.net)
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

use File::Spec::Functions qw/catfile/;
our @PODFILES;
BEGIN {
	@PODFILES = (
		catfile($FindBin::Bin,qw/ .. lib File Replace.pm /),
		catfile($FindBin::Bin,qw/ .. lib Tie Handle Base.pm /),
		catfile($FindBin::Bin,qw/ .. lib Tie Handle Argv.pm /),
		catfile($FindBin::Bin,qw/ .. lib File Replace Inplace.pm /),
		catfile($FindBin::Bin,qw/ .. lib File Replace DualHandle.pm /),
		catfile($FindBin::Bin,qw/ .. lib File Replace SingleHandle.pm /),
	);
}

use Test::More $AUTHOR_TESTS ? (tests=>1*@PODFILES+2)
	: (skip_all=>'author POD tests');

use Test::Pod;

for my $podfile (@PODFILES) {
	pod_file_ok($podfile);
}

use Capture::Tiny qw/capture_merged/;
use Cwd qw/getcwd/;
use File::Temp qw/tempdir/;
subtest 'verbatim code' => sub {
	## no critic (ProhibitStringyEval, RequireBriefOpen, RequireCarping)
	my $verb_thb = getverbatim($PODFILES[1], qr/\b(?:synopsis|examples)\b/i);
	is @$verb_thb, 4, 'Tie::Handle::Base verbatim block count'
		or diag explain $verb_thb;
	eval("use warnings; use strict; $$verb_thb[0]; 1") or fail($@);
	{
		my $filename = newtempfn;
		is capture_merged {
			eval("use warnings; use strict; $$verb_thb[1]; 1") or fail($@);
		}, "Debug: Output 'Hello, World'\n", 'my tied handle works 1';
		is slurp($filename), "Hello, World", 'my tied handle works 2';
	}
	{
		eval("use warnings; use strict; $$verb_thb[2]; 1") or fail($@);
		is capture_merged {
			my $fh = Tie::Handle::Debug->new;
			open $fh, '<', '/etc/passwd' or die $!;
			my $x = <$fh>;
			seek $fh, 0, 0;
			close $x;
		}, qq{"TIEHANDLE"\n("OPEN", "<", "/etc/passwd")\n"FILENO"\n}
			.qq{"READLINE"\n("SEEK", 0, 0)\n"DESTROY"\n},
			'Tie::Handle::Debug works';
	}
	{
		eval("use warnings; use strict; $$verb_thb[3]; 1") or fail($@);
		open my $fh0, '>', \my $main or die $!;
		open my $fh1, '>', \my $one or die $!;
		open my $fh2, '>', \my $two or die $!;
		my $teefh = Tie::Handle::Tee->new($fh0,$fh1,$fh2);
		print $teefh "Hello";
		printf $teefh ", %s!", "World";
		syswrite $teefh, "xy\nz", 1, 2;
		close $teefh;
		close $fh1;
		close $fh2;
		use Data::Dump;
		is $main, "Hello, World!\n", 'Tie::Handle::Tee main';
		is $one,  "Hello, World!\n", 'Tie::Handle::Tee one';
		is $two,  "Hello, World!\n", 'Tie::Handle::Tee two';
	}
	
	my $verb_fr = getverbatim($PODFILES[0], qr/\bsynopsis\b/i);
	is @$verb_fr, 3, 'File::Replace verbatim block count'
		or diag explain $verb_fr;
	{
		my $filename = newtempfn("Foo\nBar\nQuz\n");
		eval("use warnings; use strict; $$verb_fr[0]; 1") or fail($@);
		is slurp($filename), "X: Foo\nX: Bar\nX: Quz\n", 'File::Replace synposis 1';
		eval("use warnings; use strict; $$verb_fr[1]; 1") or fail($@);
		is slurp($filename), "Y: X: Foo\nY: X: Bar\nY: X: Quz\n", 'File::Replace synposis 2';
		eval("use warnings; use strict; $$verb_fr[2]; 1") or fail($@);
		is slurp($filename), "Z: Y: X: Foo\nZ: Y: X: Bar\nZ: Y: X: Quz\n", 'File::Replace synposis 3';
	}
	
	my $verb_av = getverbatim($PODFILES[2], qr/\b(?:synopsis)\b/i);
	is @$verb_av, 2, 'Tie::Handle::Argv verbatim block count'
		or diag explain $verb_av;
	eval("use warnings; use strict; $$verb_av[0]; 1") or fail($@);
	{
		my $filename = newtempfn("Hello,\nWorld!");
		is capture_merged {
			local (*ARGV, $.);  ## no critic (RequireInitializationForLocalVars)
			@ARGV = ($filename);  ## no critic (RequireLocalizedPunctuationVars)
			eval("use warnings; use strict; $$verb_av[1]; 1") or fail($@);
		}, "Debug: Open '$filename'\n<Hello,>\n<World!>\n", 'Tie::Handle::Argv synopsis - output ok';
		is slurp($filename), "Hello,\nWorld!", 'Tie::Handle::Argv synopsis - file ok';
	}
	
	my $verb_fri = getverbatim($PODFILES[3], qr/\b(?:synopsis)\b/i);
	is @$verb_fri, 2, 'File::Replace::Inplace verbatim block count'
		or diag explain $verb_fri;
	{
		my $prevdir = getcwd;
		my $tmpdir = tempdir(DIR=>$TEMPDIR,CLEANUP=>1);
		chdir($tmpdir) or die "chdir $tmpdir: $!";
		spew("file1.txt", "Hello\nWorld");
		spew("file2.txt", "Foo\nBar\n");
		
		is capture_merged {
			local (*ARGV, *ARGVOUT, $.);  ## no critic (RequireInitializationForLocalVars)
			eval("use warnings; use strict; $$verb_fri[0]; 1") or fail($@);
		}, "", 'File::Replace::Inplace synopsis - output ok';
		
		is slurp("file1.txt"), "H_ll_\nW_rld\n", 'File::Replace::Inplace - file 1 ok';
		is slurp("file2.txt"), "F__\nB_r\n", 'File::Replace::Inplace - file 2 ok';
		
		chdir($prevdir) or die "chdir $prevdir: $!";
	}
	## use critic
};

subtest 'other doc bits' => sub {
	my $handle = replace(newtempfn);
	# other bits from the documentation
	ok defined eof( tied(*$handle)->out_fh ), 'out eof';
	ok defined tied(*$handle)->out_fh->tell(), 'out tell';
	close $handle;
};

use Pod::Simple::SimpleTree;
sub getverbatim {
	my ($file,$regex) = @_;
	my $tree = Pod::Simple::SimpleTree->new->parse_file($file)->root;
	my ($curhead,@v);
	for my $e (@$tree) {
		next unless ref $e eq 'ARRAY';
		if (defined $curhead) {
			if ($e->[0]=~/^\Q$curhead\E/)
				{ $curhead = undef }
			elsif ($e->[0] eq 'Verbatim')
				{ push @v, $e->[2] }
		}
		elsif ($e->[0]=~/^head\d\b/ && $e->[2]=~$regex)
			{ $curhead = $e->[0] }
	}
	return \@v;
}

