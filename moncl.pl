#!/usr/bin/perl

##############################################################################
#
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

BEGIN {
    my ($wd) = $0 =~ m-(.*)/-;
    $wd ||= '.';

    chdir "$wd";
    unshift @INC, $wd;
}

use strict;
use warnings;

# let execute END routine when some signals are catched:
use sigtrap qw(die untrapped normal-signals stack-trace any error-signals);
use SMS;
use IO::Socket;
use File::Basename;
use MIME::Lite;
use MIME::Types;
use Log::Dispatch 2.23;
use Log::Dispatch::Screen;
use Log::Dispatch::File;

our $VERSION = '0.9';

my $DEBUG = 1;

my $LOGTARGET = 'Screen';
my $LOGLEVEL = $DEBUG ? 'debug' : 'error';

my @wdays = qw(So Mo Di Mi Do Fr Sa);

# FIXME: That logging stuff is not very clean so far
my %LOGTARGETS = (
    'File' => {
        name      => 'File',
        min_level => $LOGLEVEL,
        filename  => '',
        mode      => 'append',
        autoflush => 1,
        newline   => 1
    },
    'Screen' => {
        name      => 'Screen',
        min_level => $LOGLEVEL,
        stderr    => 0,
        autoflush => 1,
        newline   => 1
    }
);

my $log = Log::Dispatch->new(
    outputs => [ [ $LOGTARGET, %{ $LOGTARGETS{$LOGTARGET} } ] ],
    callbacks => sub {
        my %p = @_;
        return timefmt() . ' ' . uc( $p{level} ) . ': ' . $p{message};
    }
);

$log->info( "Loglevel: " . $LOGLEVEL );

#my $log = Log::Dispatch->new( outputs => [ [$LOGTARGET, %{$LOGTARGETS{$LOGTARGET}}] ],
#                              callbacks => sub { my %p = @_; return timefmt().' '.uc($p{level}).': '.$p{message}; } );
# my $LOGTARGET = $Cfg::LOGFILE ? 'File' : 'Screen';

my $used_configfile = '';

foreach my $conf (qw(~/.moncl /etc/moncl.conf)) {
    my ($file) = glob($conf);
    $log->debug("Trying config file $file");

    if ( defined($file) && readconfig($file) ) {
        $log->info("Using config file: $file");
        $used_configfile = $file;
        last;
    }

    $log->error("Config file: $@") if ($@);
}

if ($Cfg::LOGFILE) {
    $log->debug("Switching to Logfile $Cfg::LOGFILE");
    $log->add(
        Log::Dispatch::File->new(
            name      => 'File',
            min_level => $Cfg::LOGLEVEL,
            filename  => $Cfg::LOGFILE,
            mode      => 'append',
            autoflush => 1,
            newline   => 1
        )
    );

    $log->remove($LOGTARGET);
}
elsif ( $Cfg::LOGLEVEL ne $LOGLEVEL ) {
    $log->remove($LOGTARGET);
    $log->add(
        Log::Dispatch::Screen->new(
            name      => $LOGTARGET,
            min_level => $Cfg::LOGLEVEL,
            stderr    => 0,
            mode      => 'append',
            autoflush => 1,
            newline   => 1
        )
    );
    $log->info( "New loglevel: " . $Cfg::LOGLEVEL );
}

# ====================================

my $maxdelta_t = 3;

my $PROTOCOL  = '0004';
my $SEPARATOR = ':';

my %ALARMTYPES = (
    0 => 'Melderalarmierung (0)',
    1 => 'Melderalarmierung (1)',
    2 => 'Feueralarm',
    3 => 'Probelalarm',
    4 => 'Zivilschutzalarm',
    5 => 'Warnung',
    6 => 'Entwarnung'
);

my %ERRORCODES = (
    '000' => "unknown error",
    '001' => "not logged in",
    '002' => "not authorized",
    '003' => "login error",
    '004' => "protocoll error",
    '005' => "not implemented",
    '006' => "hardware fault",
    '007' => "write fault",
    '008' => "version error",
    '009' => "function disabled"
);

my %COMMANDS = (
    210 => 'Inquiry',
    220 => 'Login',
    299 => 'Logoff',
    202 => 'Keepalive',
    203 => 'Channel Info',
    204 => 'Audio Recording'
);

my @INQUIRY_KEYS = qw(end name os version protocol plugins);

my %CHANNEL_MODULES = (
    2**0 => 'ZVEI',
    2**1 => 'FMS',
    2**2 => 'POCSAC512',
    2**3 => 'POCSAC1200'
);

$log->notice("Trying to connect to $Cfg::HOST");

my $socket = IO::Socket::INET->new(
    PeerAddr => $Cfg::HOST,
    PeerPort => $Cfg::PORT,
    Proto    => 'tcp',
    Type     => SOCK_STREAM
) or die("Could not connect: $@\n");

my $mimetypes = MIME::Types->new;

$socket->autoflush(1);
binmode( $socket, ':crlf' );

# Send inquiry to find out server's capabilities
command('210');

my %lastalarm      = ();
my %server_info    = ();
my @recorded_loops = ();

while ( my $line = <$socket> ) {
    chomp($line);

    ( $line, my $comment ) = split( /;/, $line );
    my ( $cmd, @params ) = split( /$SEPARATOR/, $line );

    if ( $cmd eq '100' )    # OK
    {
        $log->debug("Ok from server.");
    }
    elsif ( $cmd eq '101' )    # ERROR
    {
        my $errmsg = $ERRORCODES{ $params[0] } || '?';
        $log->error("Error $params[0]: $errmsg");

        if ( $params[0] eq '001' ) {

            # Login necessary. Doing that:
            command( '220', hexdump($Cfg::USER), hexdump($Cfg::PASS),
                $PROTOCOL );
        }
        elsif ( $params[0] eq '003' ) {

            # Login error
            exit(1);
        }
    }
    elsif ( $cmd eq '103' )    # Channel Info
    {
        my $channel_num      = $params[0];
        my $channel_name     = textdecode( $params[1] );
        my $channel_features = join( ', ', moduledecode( $params[2] ) )
            || 'none';

        $log->info("#$channel_num: $channel_name ($channel_features)");
    }
    elsif ( $cmd eq '104' )    # Recording response
    {
        my $filename = textdecode( $params[2] );
        if ( $params[1] == 0 ) {
            $log->info("stopped recording: $filename");
            $log->debug( 'recording relevant for loops: '
                    . join( ', ', @recorded_loops ) );

            if ($Cfg::AUDIO_PROCESSOR) {
                my $compressedfile = `$Cfg::AUDIO_PROCESSOR $filename`;
                chomp($compressedfile);
                if ($compressedfile) {
                    $filename = $compressedfile;
                }
                else {
                    $log->warning("audioconverting failed");
                }
            }

            if ($filename) {

                # write description file
                write_desc_file( \@recorded_loops, $filename );

                # send email
                my $mail_count
                    = send_recording_email( \@recorded_loops, $filename );
                $log->info("sent emails to $mail_count recipient(s)");

                # send wap push
                eval { send_recording_sms( \@recorded_loops, $filename ); };
                $log->error("wap push failed: $@") if $@;
            }
            else {
                $log->error("recorded file not found");
            }

            @recorded_loops = ();
        }
        elsif ( $params[1] == 1 ) {
            $log->info("started recording: $filename");
        }
        elsif ( $params[1] == 2 ) {
            $log->info("continue recording: $filename");
        }
    }
    elsif ( $cmd eq '111' )    # Inquiry response
    {
        my $value
            = ( $params[0] == 3 || $params[0] == 4 )
            ? $params[1]
            : textdecode( $params[1] );
        $server_info{ $INQUIRY_KEYS[ $params[0] ] || $params[0] } = $value;

        if ( $params[0] == 0 )    # End of Inquiry response
        {
            $log->notice(
                sprintf( 'connected: %s %s ver.%d protocol.%d',
                    @server_info{qw(name os version protocol)} )
            );

            # Inquiry was successful, so now request channel info:
            command('203');
        }
    }
    elsif ( $cmd eq '300' )       # ZVEI Alarm
    {
        my %alarmdata = ();
        @alarmdata{qw(time channel loop type text)} = @params;

        # 0    1                 2               3                        4
        # Zeit:Kanalnummer(char):Schleife(text5):Sirenenalarmierung(char):Text

        my $loopdata = $Cfg::LOOPS{ $alarmdata{loop} }
            || $Cfg::LOOPS{default};
        my $who = $loopdata->{name} || $alarmdata{loop};

        if (   $alarmdata{time} - ( $lastalarm{time} || 0 ) <= $maxdelta_t
            && $alarmdata{loop} == $lastalarm{loop} )
        {
            my $msg = sprintf( "%s: %s %s",
                timefmt( $alarmdata{time} ),
                $ALARMTYPES{ $alarmdata{type} }, $who );
            $log->notice($msg);

            # trigger recording
            command( '204', $alarmdata{channel}, $Cfg::RECORDING_LENGTH );

            # store loop number for sending audio recording
            push( @recorded_loops, $alarmdata{loop} );

            # send emails
            my $mail_count
                = send_alarm_email( $alarmdata{loop}, $alarmdata{type},
                $alarmdata{time} );
            $log->info("sent emails to $mail_count recipient(s)");

            #send sms
            eval {
                send_sms( $alarmdata{loop}, $alarmdata{type},
                    $alarmdata{time} );
            };
            $log->error("sending sms failed: $@") if $@;

            #reset lastalarm
            %lastalarm = ();
        }
        else {
            $log->debug(
                timefmt( $alarmdata{time} ) . ": Single quintet $who" );
            %lastalarm = %alarmdata;
        }
    }
    else {
        $log->debug($line);
    }
}

# ==================================

sub readconfig {
    my $configfile = shift;

    package Cfg;

    # Setting config defaults
    our $HOST = 'localhost';
    our $PORT = 9333;
    our $USER = '';
    our $PASS = '';

    our $MAIL_FROM   = 'user@host';
    our $MAIL_SERVER = 'localhost';
    our $MAIL_USER   = '';
    our $MAIL_PASS   = '';

    our $SMS_FROM         = '';
    our $SMS_PROVIDER     = '';
    our $SMSKAUFEN_USER   = '';
    our $SMSKAUFEN_APIKEY = '';
    our $CATELL_API_ID    = '';
    our $CATELL_USER      = '';
    our $CATELL_PASS      = '';

    our $AUDIO_PROCESSOR = '';
    our $BASE_URL        = '';

    # Log levels:
    # debug info notice warning error critical alert emergency
    our $LOGLEVEL = 'warning';
    our $LOGFILE  = '';

    our $RECORDING_LENGTH = 30;

    our %PEOPLE = ();
    our %LOOPS  = ();

    return do $configfile;
}

# Send a command to server
sub command {
    my $cmd = join( $SEPARATOR, @_ );
    $log->info("Sending $cmd ($COMMANDS{$_[0]})");
    print $socket "$cmd\n";
}

# Format an epoch te value human readable
sub timefmt {
    my $epoch = shift || time();

    my @timedate = localtime($epoch);
    $timedate[4]++;
    $timedate[5] += 1900;
    $timedate[6] = $wdays[ $timedate[6] ];

    return (
        sprintf( '%s,%02d.%02d.%d %02d:%02d:%02d',
            @timedate[ 6, 3, 4, 5, 2, 1, 0 ] )
    );
}

# Convert hexdumped strings to readable ones
sub textdecode {
    my $code   = shift;
    my $decode = '';
    my $i      = 0;

    while ( defined($code) && ( my $chr = substr( $code, $i, 2 ) ) ) {
        $decode .= chr( hex($chr) );
        $i += 2;
    }

    return $decode;
}

# Decode loaded modules from channel info
sub moduledecode {
    my $val            = shift;
    my @loaded_modules = ();

    foreach my $module ( keys(%CHANNEL_MODULES) ) {
        push @loaded_modules, $CHANNEL_MODULES{$module} if $val & $module;
    }

    return @loaded_modules;
}

# Hexdump strings
sub hexdump {
    my $text = shift;

    my $code = '';
    foreach my $chr ( split( //, $text ) ) {
        $code .= sprintf( '%x', ord($chr) );
    }

    return $code;
}

# Generate an email message-id
sub msgid {
    my $from = shift || 'root@localhost';

    my @timedate = localtime( time() );
    $timedate[4]++;
    $timedate[5] += 1900;

    return sprintf(
        '<%d%02d%02d%02d%02d.%05d.%s>',
        @timedate[ 5, 4, 3, 2, 1 ],
        rand( $timedate[0] * 1694 ), $from
    );
}

# Get a list of recipients for the given notification kind and list of loops
sub get_recipients {
    my ( $type, @loops ) = @_;

    my %recipients = ();

    foreach my $loop (@loops) {
        foreach ( @{ $Cfg::LOOPS{$loop}->{$type} } ) {
            $recipients{$_} = 1;
        }
    }

    # FIXME: Make using default loop optional
    if ( keys %recipients == 0 ) {
        foreach ( @{ $Cfg::LOOPS{default}->{$type} } ) {
            $recipients{$_} = 1;
        }
    }

    my @to = grep {
               ref( $Cfg::PEOPLE{$_} )
            && $Cfg::PEOPLE{$_}->{$type}
            && ( $_ = $Cfg::PEOPLE{$_}->{$type} )
    } keys(%recipients);

    return @to;
}

# Send an email notifying about an alarm
sub send_alarm_email {
    my ( $loop, $type, $time, $file ) = @_;

    my $who  = $Cfg::LOOPS{$loop}->{name} || $loop;
    my $what = $ALARMTYPES{$type}         || $type;

    my @to = get_recipients( 'email', $loop );

    my $text = sprintf( "%s: %s %s", timefmt(), $what, $who );

    return send_email( \@to, "$what $who", $text );
}

# Write loop numbers and names to file with same basename as recording file
sub write_desc_file {
    my ( $loops, $file ) = @_;

    my $desc_file_name
        = join( '', ( fileparse $file, qr/\.[^.]*/ )[ 1, 0 ] ) . ".desc";

    if ( open DESC, ">$desc_file_name" ) {
        $log->info("writing description file $desc_file_name");

        foreach my $loop (@$loops) {
            my $name = $Cfg::LOOPS{$loop}->{name} || '';
            print DESC "$loop\t$name\n";
        }
        close DESC;
    }
    else {
        $log->error("failed writing descript to $desc_file_name: $!");
    }
}

# Send a recorded soundfile via email
sub send_recording_email {
    my ( $loops, $file ) = @_;

    my @to = get_recipients( 'email', @$loops );

    return send_email(
        \@to,
        "Letzte Aufnahme",
        "Mitschnitt des Funkverkehrs nach der letzten Alarmierung", $file
    );
}

# Generic email sender
sub send_email {
    my ( $to, $subject, $text, $file ) = @_;

    my $to_count = 0;
    if ( ref($to) eq 'ARRAY' ) {
        $to_count = scalar(@$to);
    }
    else {
        $to_count = 1;
    }

    return 0 unless $to_count;

    my $mail = MIME::Lite->new(
        From         => $Cfg::MAIL_FROM,
        To           => join(', ', @$to),
        Subject      => $subject,
        'Message-ID' => msgid($Cfg::MAIL_FROM),
        Precedence   => 'bulk',
        Type         => 'TEXT',
        Data         => $text
    );

    if ($file) {
        my $mtype = $mimetypes->mimeTypeOf($file) || 'audio/x-raw-int';
        $mail->attach(
            Type        => "$mtype",
            Disposition => 'attachment',
            Path        => $file
        );
    }

    my %auth = ();

    %auth = (
        AuthUser => $Cfg::MAIL_USER,
        AuthPass => $Cfg::MAIL_PASS
    ) if ($Cfg::MAIL_USER);

    eval {
        $mail->send(
            'smtp',
            $Cfg::MAIL_SERVER,
            Timeout => 60,
            Hello   => 'alarm.goessenreuth.de',
            %auth
        );
    };

    $log->error("sending email failed: $@") if ($@);

    return $to_count;
}

# Send an GSM text message (SMS) notifying about an alarm
sub send_sms {
    my ( $loop, $type, $time ) = @_;

    my $who  = $Cfg::LOOPS{$loop}->{name} || $loop;
    my $what = $ALARMTYPES{$type}         || $type;
    my @to = get_recipients( 'sms', $loop );

    if (@to) {
        $log->info(
            "SMS to " . scalar(@to) . " number(s) with text \"$what $who\"" );

        my $res = SMS::send( $Cfg::SMS_FROM, \@to, $who, $what );

        $log->debug($res);
    }
    else {
        $log->info("no short message sent because of no recipients.");
    }
}

# Send an GSM message (WAP Push) pointing to the recorded audio file
sub send_recording_sms {
    my ( $loops, $file ) = @_;

    my @to = get_recipients( 'wappush', @$loops );

    if (@to) {
        $log->info( "WAP-push to " . scalar(@to) . " number(s)" );

        my $res = SMS::send_wappush( $Cfg::SMS_FROM, \@to, "Funkmitschnitt",
            $Cfg::BASE_URL . basename($file) );
        $log->debug($res);
    }
    else {
        $log->info("no WAP-push sent because of no recipients.");
    }

}

# Close socket and log a message when terminating
END {
    if ($socket) {
        command(299);
        close($socket);
    }
    $log->notice("Exiting.");
}
