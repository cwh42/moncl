#!/usr/bin/perl -w

##############################################################################
#
# This script is part of
# moncl - an email and short message alerting client for monitord
# Copyright (C) 2009 Christopher Hofmann <cwh@webeve.de> 
#
# ---------------------------------------------------------------------------
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin St, Fifth Floor, Boston, MA 02110, USA
#
###############################################################################

use strict;

my $SOX = '/usr/bin/sox';
my $PLAY = '/usr/bin/play';
my $gain = -2.5;

my @freq = qw(2400 1060 1160 1270 1400 1530 1670 1830 2000 2200 2600);
my %dtmf = ( A => [675,1240], P => [675,1860], ZA => [675,825], ZW => [675,2280], ZE => [675,1010], M => [] );
my $dtmf_len = 5;

my $pager_freq = 2600;
my $pager_tone_len = 0.24;
my $pager_pause_len = $pager_tone_len;
my $pager_tone_count = 10;

my $loop = shift(@ARGV);
my $type = uc(shift(@ARGV));
my $file = shift(@ARGV);

help('Invalid NUMBER.') unless(defined($loop) && $loop =~ /^\d+$/);
help('Invalid TYPE.') if($type && !exists($dtmf{$type}));

my $zvei = '';
my $last_digit = undef;

foreach my $digit (split(//,$loop)) {
    $digit = 10 if defined($last_digit) && $digit == $last_digit;
    $zvei .= tone(0.07, $freq[$digit]);
    $last_digit = $digit;
}

if( $type eq 'M' ) {
    $type = pager();
}
else {
    $type = $type ? " \"|$SOX -n -p synth $dtmf_len sin $dtmf{$type}->[0] synth $dtmf_len sin mix $dtmf{$type}->[1]\"" : '';
}

my $system = silence().$zvei.silence().$zvei.silence().$type.silence(0.07);

if(defined($file)) {
    $system = $SOX.$system." --comment '$loop $type' $file gain $gain";
}
else {
    $system = $PLAY.$system." gain $gain";
}

#print "$system\n";
system($system);

sub silence {
    my $len = $_[0] || 0.6;
    return " \"|$SOX -n -p trim 0 $len\"";
}

sub tone {
    my ($len, $freq) = @_;
    return " \"|$SOX -n -p synth $len sine $freq\"";
}

sub pager {
    my $cmd = '';

    for(1..$pager_tone_count) {
        $cmd .= tone($pager_tone_len, $pager_freq).silence($pager_pause_len);
    }

    return $cmd;
}

sub help {
    print "Error: $_[0]\n" if($_[0]);

    print << "END";
Usage: $0 <NUMBER> [TYPE] [AUDIOFILE]

NUMBER is typically a 5 digit integer. More or less digits are supported but the result
may be useless.

TYPE can be omitted or be one of A (=Alarm), P (=Probealarm), ZA (=Zivilschutzalarm),
ZW (=Zivilschutzwarnung), ZE (=Zivilschutzentwarnung) or M (=Melderalarmierung)

If AUDIOFILE is omitted sound is played using system's default sound card. AUDIOFILE's
audioformat is determined by its filesuffix. See 'man soxformat' for supported audiofomats.
END

    exit(1);
}
