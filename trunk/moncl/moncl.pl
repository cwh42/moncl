#!/usr/bin/perl -w

use strict;
use IO::Socket;
use MIME::Lite;
use Net::Clickatell;

my $maxdelta_t = 3;
my $recording_length = 25;

my $mail_from = 'ffw@goessenreuth.de';
my $mail_server = 'mail.webeve.de';
my $mail_user = 'cwh';
my $mail_pass = 'ZDa!DaH?';
#my $mail_server = 'relay.suse.de';
#my $mail_user = '';
#my $mail_pass = '';

my $sms_from = '491702636472';
my $catell_api_id = '3187455';
my $catell_user = 'cwhofmann';
my $catell_pass = 'dam0kles';

my %people = ( cwh => { name => 'Christopher Hofmann', phone => '01702636472', email => 'cwh@webeve.de' },
               seggl => { name => 'Markus Matussek', phone => '01718813863', email => 'markus.matussek@glendimplex.de' },
               andrea => { name => 'Andrea Herzog', phone => '015111701351', email => 'la-andi@gmx.de' },
               achim => { name => 'Achim Geyer', phone => '01607634981', email => 'geyer.achim@landkreis-kulmbach.de' },
               xaver => { name => 'Alexander Schneider', phone => '015112446132', email => 'alexander.schneider@novem.de' },
               rainer => { name => 'Rainer Hartmann', phone => '01604616195', email => '' },
               langers => { name => 'Michael Hartmann', phone => '01717788775', email => 'harmic80@webeve.de' },
               langers_arbeit => { name => 'Michael Hartmann', phone => '', email => 'Michael.Hartmann@fob.lsv.de' },
               langerswolfgang => { name => 'Wolfgang Hartmann', phone => '01605234235', email => '' } );

# cwh => { name => '', phone => '', email => '' }

my %loops = ( default => { email => [qw(cwh)] },
	      23154 => { name => 'FF Goessenreuth',
                         email => [qw(cwh seggl achim xaver langers langers_arbeit)],
                         sms => [qw(cwh seggl andrea xaver rainer langers langerswolfgang)] },
              23152 => { name => 'FF Hi. od. La. (152)',
                         email => [qw(cwh)],
                         sms => [qw(cwh)] },
              23153 => { name => 'FF Hi. od. La. (153)',
                         email => [qw(cwh)],
                         sms => [qw(cwh)] },
              23139 => { name => 'FF Marktleugast',
                         email => [],
                         sms => [] },
              23598 => { name => 'Notfallseelsorge',
                         email => [],
                         sms => [] },
              23591 => { name => 'THW',
                         email => [],
                         sms => [] } );

# ====================================

my $PROTOCOL = '0004';

my %alarmtypes = ( 0 => 'Melderalarmierung (0)',
                   1 => 'Melderalarmierung (1)',
                   2 => 'Feueralarm',
                   3 => 'Probelalarm',
                   4 => 'Zivilschutzalarm',
                   5 => 'Warnung',
                   6 => 'Entwarnung' );

my %errorcodes = ( '000' => "unknown error", 
                   '001' => "not logged in",      
                   '002' => "not authorized",     
                   '003' => "login error",        
                   '004' => "protocoll error",    
                   '005' => "not implemented",    
                   '006' => "hardware fault",     
                   '007' => "write fault",        
                   '008' => "version error",      
                   '009' => "function disabled" );

my @inquiry_keys = qw(end name os version protocol plugins);

my @wdays = qw(So Mo Di Mi Do Fr Sa);

# ------------------------------------

my $socket = IO::Socket::INET->new( PeerAddr => 'localhost',
                                    PeerPort => 9333,
                                    Proto => 'tcp',
                                    Type => SOCK_STREAM )
    or die("Could not connect: $@\n");

$socket->autoflush(1);

# Unfortunately monitord always uses DOS line endings:
binmode($socket, ':crlf');

# Send a command to server
sub command
{
    print timefmt().": Sending $_[0]\n";
    print $socket "$_[0]\n";
}

# Format an epoch te value human readable
sub timefmt
{
    my $epoch = shift || time();

    my @timedate = localtime($epoch);
    $timedate[4]++;
    $timedate[5] += 1900;
    $timedate[6] = $wdays[$timedate[6]];

    return(sprintf('%s, %02d.%02d.%d %02d:%02d:%02d', @timedate[6,3,4,5,2,1,0]));
}

# Convert hexdumped strings to readable ones
sub textdecode
{
    my $code = shift;
    my $decode = '';
    my $i = 0;

    while( defined($code) && ( my $chr = substr( $code, $i, 2 ) ) )
    {
        $decode .= chr(hex($chr));
	$i+=2;
    }

    return $decode;
}

# Generate an email message-id
sub msgid
{
    my $from = shift || 'root@localhost';

    my @timedate = localtime(time());
    $timedate[4]++;
    $timedate[5] += 1900;

    return sprintf('<%d%02d%02d%02d%02d.%05d.%s>', @timedate[5,4,3,2,1], rand($timedate[0]*1694), $from);
}

# Send an email notifying about an alarm
sub send_email
{
    my ($loop, $type, $time, $file ) = @_;

    my $loopdata = $loops{$loop} || $loops{default};

    my $who = $loopdata->{name} || $loop;
    my $what = $alarmtypes{$type} || $type;
    my $to = $loopdata->{email} || [];

    my $text = sprintf( "%s: %s %s", timefmt(), $what, $who);

    my $mail = MIME::Lite->new( From => "FF Alarmierung <$mail_from>",
                                Subject => "$what $who",
                                'Message-ID' => msgid($mail_from),
                                Precedence => 'bulk',
                                Type => 'multipart/mixed' );

    my @to = grep {ref($people{$_}) && $people{$_}->{email} && ($_ = $people{$_}->{email})} @$to;

    if(@to > 0)
    {
        $mail->add("To" => \@to);
    }
    else
    {
        $mail->add("To" => $loops{default}->{email}||[]);
    }

    $mail->attach( Type => 'TEXT',
                   Data => $text );

    if( $file )
    {
        $mail->attach( Type => 'audio/mpeg',
                       Path => $file );
    }

    #print $mail->as_string();
    $mail->send('smtp',
		$mail_server,
		Timeout => 60,
		Hello => '127.0.0.1',
                AuthUser => $mail_user,
		AuthPass => $mail_pass);
}

# Temporary hack:
# Send and recorded soundfile via email
sub tmp_send_mail
{
    my ( $file ) = @_;

    my $mail = MIME::Lite->new( From => "FF Alarmierung <$mail_from>",
                                Subject => "Letzte Aufnahme",
                                'Message-ID' => msgid($mail_from),
                                Precedence => 'bulk',
                                Type => 'multipart/mixed' );
    $mail->add("To" => $loops{default}->{email}||[]);

    $mail->attach( Type => 'audio/wav',
                   Path => $file );

    #print $mail->as_string();
    $mail->send('smtp',
		$mail_server,
		Timeout => 60,
		Hello => '127.0.0.1',
                AuthUser => $mail_user,
		AuthPass => $mail_pass);
}

# Send an GSM text message (SMS) notifying about an alarm
sub send_sms
{
    my ($loop, $type, $time) = @_;

    my $loopdata = $loops{$loop} || $loops{default};

    my $who = $loopdata->{name} || $loop;
    my $what = $alarmtypes{$type} || $type;
    my $to = $loopdata->{sms} || [];

    my $clickatell = Net::Clickatell->new( API_ID => $catell_api_id,
                                           USERNAME =>$catell_user,
                                           PASSWORD =>$catell_pass );

    my @to = grep {ref($people{$_}) && $people{$_}->{phone} && ($_ = $people{$_}->{phone})} @$to;

    if(@to)
    {
        print "\tSMS to ".scalar(@to)." number(s) with text \"$what $who\"\n";
        print "\t".$clickatell->sendBasicSMSMessage($sms_from,
                                                    join(',',@to),
                                                    "$what $who")."\n";
    }
}

# Send inquiry to find out server's capabilities
command('210');

my %lastalarm = ();
my %server_info = ();

while( my $line = <$socket> )
{
    chomp($line);

    ($line, my $comment) = split(/;/, $line);
    my ($cmd, @params) = split(/:/, $line);

    if( $cmd eq '100' )
    {
        print timefmt().": Ok\n";
    }
    elsif( $cmd eq '101' )
    {
        my $errmsg = $errorcodes{$params[0]} || '?';
        print timefmt().": Error $params[0]: $errmsg\n";
    }
    elsif( $cmd eq '104' )
    {
        my $filename = textdecode($params[2]);
        if( $params[1] == 0 )
        {
            print timefmt().": stopped recording: $filename\n";

            # ugly quick hack, needs to be fixed:
            my $compressedfile = `/home/cwh/bin/audioencode $filename`;
            chomp($compressedfile);
            print "\taudioconverting failed\n" unless $compressedfile;

            eval { tmp_send_mail($compressedfile) };
            print "\tsending email failed: $@\n" if $@;
        }
        elsif( $params[1] == 1 )
        {
            print timefmt().": started recording: $filename\n";
        }
        elsif( $params[1] == 2 )
        {
            print timefmt().": continue recording: $filename\n";
        }
    }
    elsif( $cmd eq '111' )
    {
        my $value = ( $params[0] == 3 || $params[0] == 4 ) ? $params[1] : textdecode($params[1]);
        $server_info{$inquiry_keys[$params[0]]||$params[0]} = $value;

        printf("%s: %s %s ver.%d protocol.%d\n", timefmt(), @server_info{qw(name os version protocol)}) if $params[0] == 0;
    }
    elsif( $cmd eq '300' )
    {
        my %alarmdata = ();
        @alarmdata{qw(time channel loop type text)} = @params;

        # 0    1                 2               3                        4
        # Zeit:Kanalnummer(char):Schleife(text5):Sirenenalarmierung(char):Text

	my $loopdata = $loops{$alarmdata{loop}} || $loops{default};
	my $who = $loopdata->{name} || $alarmdata{loop};

        if( $alarmdata{time} - ($lastalarm{time}||0) <= $maxdelta_t && $alarmdata{loop} == $lastalarm{loop} )
        {
	    # print message to STDOUT
            my $msg = sprintf( "%s: %s %s", timefmt($alarmdata{time}), $alarmtypes{$alarmdata{type}}, $who);
            print $msg."\n";

            # trigger recording
            command("204:$alarmdata{channel}:$recording_length");

	    # send emails
            eval { send_email($alarmdata{loop}, $alarmdata{type}, $alarmdata{time}) };

            if($@)
            {
                print "\tsending email failed: $@\n";
            }
            else
            {
                print "\tsent email\n";
            }

	    #send sms
            eval { send_sms($alarmdata{loop}, $alarmdata{type}, $alarmdata{time}) };
            print "\tsending sms failed: $@\n" if $@;

            #reset lastalarm
            %lastalarm = ();
        }
        else
        {
            print timefmt($alarmdata{time}).": Single quintet $who\n";
            %lastalarm = %alarmdata;
        }
    }
    else
    {
        print timefmt().": $line\n";
    }
}

close($socket);
