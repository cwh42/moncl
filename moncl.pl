#!/usr/bin/perl -w

use strict;
# let execute END routine when some signals are catched:
use sigtrap qw(die untrapped normal-signals stack-trace any error-signals);
use IO::Socket;
use Time::HiRes qw(sleep);
use MIME::Lite;
use Log::Dispatch 2.23;
use Net::Clickatell;

my $CONFIGFILE = 'moncl.conf';

{ package Cfg; 

  # Setting config defaults
  our $HOST = 'localhost';
  our $PORT = 9333;
  our $USER = '';
  our $PASS = '';

  our $MAIL_FROM = 'user@host';
  our $MAIL_SERVER = 'localhost';
  our $MAIL_USER = '';
  our $MAIL_PASS = '';

  our $SMS_FROM = '';
  our $CATELL_API_ID = '';
  our $CATELL_USER = '';
  our $CATELL_PASS = '';

  # Log levels:
  # debug info notice warning error critical alert emergency
  our $LOGLEVEL = 'warning';
  our $LOGFILE = '';

  our $RECORDING_LENGTH = 25;

  do $CONFIGFILE or warn("Could not read config file $CONFIGFILE\n")
}

my %people = ( cwh => { name => 'Christopher Hofmann', phone => '01702636472', email => 'cwh@webeve.de' },
               seggl => { name => 'Markus Matussek', phone => '01718813863', email => 'markus.matussek@glendimplex.de' },
               andrea => { name => 'Andrea Herzog', phone => '015111701351', email => 'la-andi@gmx.de' },
               achim => { name => 'Achim Geyer', phone => '01607634981', email => 'geyer.achim@landkreis-kulmbach.de' },
               xaver => { name => 'Alexander Schneider', phone => '015112446132', email => 'alexander.schneider@novem.de' },
               rainer => { name => 'Rainer Hartmann', phone => '01604616195', email => '' },
               langers => { name => 'Michael Hartmann', phone => '01717788775', email => 'harmic80@webeve.de' },
               langers_arbeit => { name => 'Michael Hartmann', phone => '', email => 'Michael.Hartmann@fob.lsv.de' },
               langerswolfgang => { name => 'Wolfgang Hartmann', phone => '01605234235', email => '' },
               gernot => => { name => 'Gernot Geyer', phone => '01709233287', email => '' },
               schlaubi => { name => 'Markus Schneider', phone => '01604434387', email => '' });

# cwh => { name => '', phone => '', email => '' }

my %loops = ( default => { email => [qw(cwh)] },
	      23154 => { name => 'FF Goessenreuth',
                         email => [qw(cwh seggl achim xaver langers langers_arbeit)],
                         sms => [qw(cwh seggl andrea xaver rainer langers langerswolfgang gernot schlaubi)] },
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

my $maxdelta_t = 3;

my $PROTOCOL = '0004';
my $SEPARATOR = ':';

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

my %COMMANDS = ( 210 => 'Inquiry',
                 220 => 'Login',
                 299 => 'Logoff',
                 202 => 'Keepalive',
                 203 => 'Channel Info',
                 204 => 'Audio Recording' );

my @inquiry_keys = qw(end name os version protocol plugins);

my @wdays = qw(So Mo Di Mi Do Fr Sa);

# ------------------------------------

my $LOGTARGET = $Cfg::LOGFILE ? 'File' : 'Screen';

my %LOGTARGETS = ('File' => { min_level => $Cfg::LOGLEVEL,
                              filename  => $Cfg::LOGFILE,
                              mode      => 'append',
                              autoflush => 1,
                              newline   => 1 },
                  'Screen' => { min_level => $Cfg::LOGLEVEL,
                                stderr => 0,
                                autoflush => 1,
                                newline   => 1 } );
    
my $log = Log::Dispatch->new( outputs => [ [$LOGTARGET, $LOGTARGETS{$LOGTARGET}] ],
                              callbacks => sub { my %p = @_; return timefmt().' '.uc($p{level}).': '.$p{message}; } );

$log->info("Loglevel: ".$Cfg::LOGLEVEL);
$log->notice("Trying to connect to $Cfg::HOST");

my $socket = IO::Socket::INET->new( PeerAddr => $Cfg::HOST,
                                    PeerPort => $Cfg::PORT,
                                    Proto => 'tcp',
                                    Type => SOCK_STREAM )
    or die("Could not connect: $@\n");

$socket->autoflush(1);
binmode($socket, ':crlf');

# ------------------------------------

# Send a command to server
sub command
{
    my $cmd = join($SEPARATOR, @_);
    $log->info("Sending $cmd ($COMMANDS{$_[0]})");
    print $socket "$cmd\n";
}

# Format an epoch te value human readable
sub timefmt
{
    my $epoch = shift || time();

    my @timedate = localtime($epoch);
    $timedate[4]++;
    $timedate[5] += 1900;
    $timedate[6] = $wdays[$timedate[6]];

    return(sprintf('%s,%02d.%02d.%d %02d:%02d:%02d', @timedate[6,3,4,5,2,1,0]));
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

# Hexdump strings
sub hexdump
{
    my $text = shift;

    my $code = '';
    foreach my $chr (split(//, $text))
    {
        $code .= sprintf('%x', ord($chr));
    }

    return $code;
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

    my $mail = MIME::Lite->new( From => "FF Alarmierung <$Cfg::MAIL_FROM>",
                                Subject => "$what $who",
                                'Message-ID' => msgid($Cfg::MAIL_FROM),
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

    $mail->send('smtp',
		$Cfg::MAIL_SERVER,
		Timeout => 60,
		Hello => '127.0.0.1',
                AuthUser => $Cfg::MAIL_USER,
		AuthPass => $Cfg::MAIL_PASS);
}

# Temporary hack:
# Send and recorded soundfile via email
sub tmp_send_mail
{
    my ( $file ) = @_;

    my $mail = MIME::Lite->new( From => "FF Alarmierung <$Cfg::MAIL_FROM>",
                                Subject => "Letzte Aufnahme",
                                'Message-ID' => msgid($Cfg::MAIL_FROM),
                                Precedence => 'bulk',
                                Type => 'multipart/mixed' );
    $mail->add("To" => $loops{default}->{email}||[]);

    $mail->attach( Type => 'audio/wav',
                   Path => $file );

    $mail->send('smtp',
		$Cfg::MAIL_SERVER,
		Timeout => 60,
		Hello => '127.0.0.1',
                AuthUser => $Cfg::MAIL_USER,
		AuthPass => $Cfg::MAIL_PASS);
}

# Send an GSM text message (SMS) notifying about an alarm
sub send_sms
{
    my ($loop, $type, $time) = @_;

    my $loopdata = $loops{$loop} || $loops{default};

    my $who = $loopdata->{name} || $loop;
    my $what = $alarmtypes{$type} || $type;
    my $to = $loopdata->{sms} || [];

    my $clickatell = Net::Clickatell->new( API_ID => $Cfg::CATELL_API_ID,
                                           USERNAME =>$Cfg::CATELL_USER,
                                           PASSWORD =>$Cfg::CATELL_PASS );

    my @to = grep {ref($people{$_}) && $people{$_}->{phone} && ($_ = $people{$_}->{phone})} @$to;

    if(@to)
    {
        $log->info("SMS to ".scalar(@to)." number(s) with text \"$what $who\"");
        my $res = $clickatell->sendBasicSMSMessage($Cfg::SMS_FROM,
                                                   join(',',@to),
                                                   "$what $who")."\n";
        $log->debug($res);
    }
}

# Send inquiry to find out server's capabilities
command('210');
sleep(.5);

# Request channel info
command('203');

my %lastalarm = ();
my %server_info = ();

while( my $line = <$socket> )
{
    chomp($line);

    ($line, my $comment) = split(/;/, $line);
    my ($cmd, @params) = split(/$SEPARATOR/, $line);

    if( $cmd eq '100' )
    {
        $log->debug("Ok from server.");
    }
    elsif( $cmd eq '101' )
    {
        my $errmsg = $errorcodes{$params[0]} || '?';
        $log->error("Error $params[0]: $errmsg");

        if( $params[0] eq '001' )
        {
            # Login necessary. Doing that:
            command('220', hexdump($Cfg::USER), hexdump($Cfg::PASS), $PROTOCOL);
        }
        elsif( $params[0] eq '003' )
        {
            # Login error
            exit(1);
        }
    }
    elsif( $cmd eq '104' ) # Recording response
    {
        my $filename = textdecode($params[2]);
        if( $params[1] == 0 )
        {
            $log->info("stopped recording: $filename");

            # ugly quick hack, needs to be fixed:
            my $compressedfile = `/home/cwh/bin/audioencode $filename`;
            chomp($compressedfile);
            $log->error("audioconverting failed") unless $compressedfile;

            eval { tmp_send_mail($compressedfile) };
            $log->error("sending email failed: $@") if $@;
        }
        elsif( $params[1] == 1 )
        {
            $log->info("started recording: $filename");
        }
        elsif( $params[1] == 2 )
        {
            $log->info("continue recording: $filename");
        }
    }
    elsif( $cmd eq '111' ) # Inquiry response
    {
        my $value = ( $params[0] == 3 || $params[0] == 4 ) ? $params[1] : textdecode($params[1]);
        $server_info{$inquiry_keys[$params[0]]||$params[0]} = $value;

        $log->notice(sprintf('Connected: %s %s ver.%d protocol.%d', @server_info{qw(name os version protocol)})) if $params[0] == 0;
    }
    elsif( $cmd eq '300' ) # ZVEI Alarm
    {
        my %alarmdata = ();
        @alarmdata{qw(time channel loop type text)} = @params;

        # 0    1                 2               3                        4
        # Zeit:Kanalnummer(char):Schleife(text5):Sirenenalarmierung(char):Text

	my $loopdata = $loops{$alarmdata{loop}} || $loops{default};
	my $who = $loopdata->{name} || $alarmdata{loop};

        if( $alarmdata{time} - ($lastalarm{time}||0) <= $maxdelta_t && $alarmdata{loop} == $lastalarm{loop} )
        {
            my $msg = sprintf( "%s: %s %s", timefmt($alarmdata{time}), $alarmtypes{$alarmdata{type}}, $who);
            $log->notice($msg);

            # trigger recording
            command('204', $alarmdata{channel}, $Cfg::RECORDING_LENGTH);

	    # send emails
            eval { send_email($alarmdata{loop}, $alarmdata{type}, $alarmdata{time}) };

            if($@)
            {
                $log->error("sending email failed: $@");
            }
            else
            {
                $log->info("sent email");
            }

	    #send sms
            eval { send_sms($alarmdata{loop}, $alarmdata{type}, $alarmdata{time}) };
            $log->error("sending sms failed: $@") if $@;

            #reset lastalarm
            %lastalarm = ();
        }
        else
        {
            $log->debug(timefmt($alarmdata{time}).": Single quintet $who");
            %lastalarm = %alarmdata;
        }
    }
    else
    {
        $log->debug($line);
    }
}

END
{
    if($socket)
    {
        command(299);
        close($socket);
    }
    $log->notice("Exiting.");
}
