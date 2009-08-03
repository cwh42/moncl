#!/usr/bin/perl -w

use strict;
use IO::Socket;
use MIME::Lite;
use Net::SMS::Clickatell;

my $socket = IO::Socket::INET->new( PeerAddr => 'localhost',
                                    PeerPort => 9333,
                                    Proto => 'tcp',
                                    Type => SOCK_STREAM )
    or die("Could not connect: $@\n");

my $catell_api_id = '1563210';
my $catell_user = 'cwhofmann';
my $catell_pass = 'dam0kles';
my $catell = Net::SMS::Clickatell->new( API_ID => $catell_api_id );
$catell->auth( USER => $catell_user,
               PASSWD => $catell_pass );

$/ = "\r\n";
$socket->autoflush(1);

my %dptnames = ( 23154 => 'FF Goessenreuth',
                 23153 => 'FF Hi. od La.?',
                 23152 => 'FF Hi. od La.?');

my %loops = ( 23154 => { name => 'FF Goessenreuth',
                         emails => [qw( cwh@webeve.de )],
                         numbers => [qw( 491702636472 )] } );

my %alarmtypes = ( 0 => 'Feueralarm (Still)',
                   1 => 'Feueralarm (Still)',
                   2 => 'Feueralarm',
                   3 => 'Probelalarm',
                   4 => 'Zivilschutzalarm',
                   5 => 'Warnung',
                   6 => 'Entwarnung' );

my @wdays = qw(So Mo Di Mi Do Fr Sa);

sub command
{
    print $socket $_[0].$/;
}

sub timefmt
{
    my $epoch = shift;

    my @timedate = localtime($epoch);
    $timedate[4]++;
    $timedate[5] += 1900;
    $timedate[6] = $wdays[$timedate[6]];

    return(sprintf('%d-%02d-%02d (%s) %02d:%02d:%02d', @timedate[5,4,3,6,2,1,0]));
}

sub textdecode
{
    my $code = shift;
    my $decode = '';
    my $i = 0;

    while( my $chr = substr( $code, $i, 2 ) )
    {
        $decode .= chr(hex($chr));
	$i+=2;
    }

    return $decode;
}

sub msgid
{
    my $from = shift || 'user@host';

    my @timedate = localtime(time());
    $timedate[4]++;
    $timedate[5] += 1900;

    return sprintf('<%d%02d%02d%02d%02d.%05d.%s>', @timedate[5,4,3,2,1], rand($timedate[0]*1694), $from);
}

sub send_email
{
    my ($type, $text, $file ) = @_;

    my $from = 'ffw@goessenreuth.de';

    my $mail = MIME::Lite->new( From => "FF =?utf-8?q?G=C3=B6ssenreuth?= <$from>",
                                To => 'cwh@webeve.de',
                                Subject => $type,
                                'Message-ID' => msgid($from),
                                Precedence => 'bulk',
                                Type => 'multipart/mixed' );

    $mail->attach( Type => 'TEXT',
                   Data => $text );

    if( $file )
    {
        $mail->attach( Type => 'audio/mpeg',
                       Path => $file );
    }

    #print $mail->as_string();
    $mail->send('smtp',
		'mail.webeve.de',
		Timeout=>60,
		Hello=>'127.0.0.1',
                AuthUser=>'cwh',
		AuthPass=>'ZDa!DaH?');
}

sub send_sms
{
    my ($loop, $text) = @_;

    #return 0 unless( $loop eq '23154' );

    my @phones = qw( 491702636472 );
    my $count = 0;

    foreach my $phone (@phones)
    {
        $count += $catell->sendmsg( TO => $phone,
                                    MSG => sprintf('%s %s', $loop, $text) );
    }

    return $count;
}

my @lastalarm = ();
my $recordingstart;

while( my $line = <$socket> )
{
    chomp( $line );
    my ( $cmd, @params) = split(/:/, $line );

    if( $cmd eq '300' )
    {
        # 0    1                 2               3                        4
        # Zeit:Kanalnummer(char):Schleife(text5):Sirenenalarmierung(char):Text
        my $who = $dptnames{$params[2]} || $params[2];

        if( $params[0] - $lastalarm[0] <= 2 && $params[2] == $lastalarm[2] )
        {
            # trigger recording
            my $duration = 20;
            $duration = time() - $recordingstart if(defined($recordingstart));
            command("204:1:$duration");

            my $msg = sprintf( "%s: %s %s", timefmt($params[0]), $alarmtypes{$params[3]}, $who);
            print $msg."\n";
            send_email($alarmtypes{$params[3]}, $msg);
            print "\tsent mail\n";

            my $count = send_sms($params[2], $msg);
            print "\tsent $count sms\n";
        }
        else
        {
            print timefmt($params[0]).": Einzelnes Quintett $who\n";
        }

        @lastalarm = @params;
    }
    elsif( $cmd eq '104' )
    {
        if( $params[1] == 0 )
        {
            $recordingstart = undef;
            print "Aufname beendet: $params[2]\n";
        }
        elsif( $params[1] == 1 )
        {
            $recordingstart = time();
            print "Aufname gestartet: $params[2]\n";
        }
        elsif( $params[1] == 2 )
        {
            print "Aufname verlängert: $params[2]\n";
        }
    }
    else
    {
        print "$line\n";
    }
}

close($socket);
