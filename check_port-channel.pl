#!/usr/bin/perl -w
#===============================================================================
# Auteur : Etienne Ischer
# Date   : 10/09/2013 09:16:24
# But    : Check states members of a Port-channel
#===============================================================================
use strict;
use warnings;
 
# Chargement du module
use Nagios::Plugin;
use Net::SSH2;
 
use vars qw/ $VERSION /;
 
# Version du plugin
$VERSION = '1.0';
 
my $LICENCE
  = "Ce plugin Nagios est gratuit et libre de droits, et vous pouvez l'utiliser à votre convenance."
  . ' Il est livré avec ABSOLUMENT AUCUNE GARANTIE.';
 
my $plugin_nagios = Nagios::Plugin->new(
  shortname => 'Check Port-channel state',
  usage     => 
  'Usage : %s [-H <host> or --host <host>] [-m <number> or --members <number>] [-p <port-channel-number> or --po <port-channel-number>] 
              [-s <port> or --ssh <port>] [-U <username> or --user <username>][-P <password> or --password <password>]',
  version   => $VERSION,
  license   => $LICENCE,
);
 
# Définition des arguments
# Définition de l'argument --host ou -H
$plugin_nagios->add_arg(
  spec     => 'host|H=s',
  help     => 'Host to check',
  required => 1,
);

# Définition de l'argument --members ou -m
$plugin_nagios->add_arg(
  spec     => 'members|m=s',
  help     => 'Number of members in the Port-channel',
  required => 1,
);
 
# Définition de l'argument --port-channel ou -p
$plugin_nagios->add_arg(
  spec     => 'po|p=s',
  help     => 'Number of the port-channel to check',
  required => 1,
);

# Définition de l'argument -s ou --ssh
$plugin_nagios->add_arg(
  spec     => 'ssh|s=s',
  help     => 'Port for ssh connection',
  required => 0,
);

# Définition de l'argument --user ou -U
$plugin_nagios->add_arg(
  spec     => 'user|U=s',
  help     => 'ssh username',
  required => 1,
);

# Définition de l'argument --password ou -P
$plugin_nagios->add_arg(
  spec     => 'password|P=s',
  help     => 'ssh password for username',
  required => 1,
);
 
# Activer le parsing des options de ligne de commande
$plugin_nagios->getopts;

# Variables
my $ssh         = "";
my $members     = "";
my $password    = "";
my $username    = "";
my $po          = "";
my $host        = "";
my $poinfo      = "";
my $poMembersUp = "0";
my $message_ok;
my $message_warning;
my $message_critical;

# Check arguments and get the variables
check_arguments();

# Create the SSH connection
# Create a new connection to the host:port
my $ssh2 = Net::SSH2->new();

# Connecting to host
$ssh2->connect($host, $ssh, Timeout=>5000) or die $plugin_nagios->nagios_exit( CRITICAL, "Unable to connect to host \n");

# authentification
$ssh2->auth_password($username,$password) or die $plugin_nagios->nagios_exit( CRITICAL, "Unable to login \n");

# Open a channel
my $chan2 = $ssh2->channel();
$chan2->blocking(0);
$chan2->shell();
sleep(1);

# Send command to the switch
print $chan2 "show etherchannel summary | include $po\n" or die $plugin_nagios->nagios_exit( CRITICAL, "Unable to execute this command \n");

# result handling
while (<$chan2>)
{
 my $line = $_;
 if($line =~ m/\QPo$po/i)
  {
   $poinfo = $line;
  }
}

# check if the portchannel is up
if ($poinfo =~ m/\QPo$po(SU)/)
{
 # Canonicalize horizontal whitespace:
 # $poinfo =~ s/\h+/ /g;
 
 # split it in an array
 my @membersarray = split(' ', $poinfo); 
 
 # get the interfaces
 while (<@membersarray>)
 {
  my $line = $_;
  if($line =~ m/\s*^[a-zA-Z]{2}[0-9]{1,2}\/[0-9]{0,1}\/{0,1}[0-9]{1,2}\(P\)/)
  {
   $poMembersUp ++;
  }
 }
 
 # if all members are up
 if ($poMembersUp == $members)
 {
  # create temp variable to
  open my $temp, '>', \$message_ok or die "unable to open variable: $!";
  print $temp "Port-channel $po is up. All the $members interfaces are up: ";
  # print interfaces
  while (<@membersarray>)
  {
   my $line = $_;
   if($line =~ m/\s*^[a-zA-Z]{2}[0-9]{1,2}\/[0-9]{0,1}\/{0,1}[0-9]{1,2}\(P\)/)
   {
    print $temp "- $line ";
   }
  }
  $plugin_nagios->nagios_exit( OK, $message_ok);
 } 
 elsif ($poMembersUp != $members)
 {
  open my $temp, '>', \$message_warning or die "unable to open variable: $!";
  # A member is down 
  print $temp "Port-channel $po is up. One or more interfaces are down. ";
  
  # print interfaces
  print $temp "Interfaces UP: ";
  while (<@membersarray>)
  {
   my $line = $_;
   if($line =~ m/\s*^[a-zA-Z]{2}[0-9]{1,2}\/[0-9]{0,1}\/{0,1}[0-9]{1,2}\(P\)/)
   {
    print $temp "- $line ";
   }
  }
  
  #print down interfaces
  print $temp "Interfaces DOWN: ";
  while (<@membersarray>)
  {
   my $line = $_;
   if($line =~ m/\s*^[a-zA-Z]{2}[0-9]{1,2}\/[0-9]{0,1}\/{0,1}[0-9]{1,2}\(D\)/)
   {
    print $temp "- $line ";
   }
  }
  $plugin_nagios->nagios_exit( WARNING, $message_warning);
 }
}
# if the port-channel is down
elsif ($poinfo =~ m/\QPo$po(SD)/)
{
 open my $temp, '>', \$message_critical or die "unable to open variable: $!";
 print $temp "Port-channel $po is down. All the $members interfaces are down: ";
 # Canonicalize horizontal whitespace:
 # $poinfo =~ s/\h+/ /g;
 
 # split it in an array
 my @membersarray = split(' ', $poinfo);
 
 #print down interfaces
  while (<@membersarray>)
  {
   my $line = $_;
   if($line =~ m/\s*^[a-zA-Z]{2}[0-9]{1,2}\/[0-9]{0,1}\/{0,1}[0-9]{1,2}\(D\)/)
   {
    print $temp "- $line ";
   }
  }
  $plugin_nagios->nagios_exit( CRITICAL, $message_critical);
}else
{
 open my $temp, '>', \$message_critical or die "unable to open variable: $!";
 print $temp "Port-channel $po doen't exist \n";
 $plugin_nagios->nagios_exit( CRITICAL, $message_critical);
}

# Close the connection
$chan2->close;

# Fonctions

# Check les arguments
sub check_arguments {
  # Get the hostname / ip
  if ($plugin_nagios->opts->host){
    # If it's not an ip address
    if ($plugin_nagios->opts->host !~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/)
    {
      $host = get_ip($plugin_nagios->opts->host);
    }else{
      $host = $plugin_nagios->opts->host;
    }
  }else{
    print "Host IP address not specified\n";
    print_usage();
  }
  
  # Get the number of members in a port-channel
  if ($plugin_nagios->opts->members){
    $members = $plugin_nagios->opts->members;
  }else{
    print "Members of Port-channel not defined \n";
    print_usage();
  }
  
  # Get the usersanme
  if ($plugin_nagios->opts->user){
    $username = $plugin_nagios->opts->user;
  }else{
    print "Username not defined \n";
    print_usage();
  }
  
  # Get the password
  if ($plugin_nagios->opts->password){
    $password = $plugin_nagios->opts->password;
  }else{
    print "Password not defined \n";
    print_usage();
  }
  
  # Get the portchannel
  if ($plugin_nagios->opts->po){
    $po = $plugin_nagios->opts->po;
  }else{
    print "Port-channel not defined \n";
    print_usage();
  }
  
  # Get the ssh port number
  if ($plugin_nagios->opts->ssh){
    $ssh = $plugin_nagios->opts->ssh;
  }else{
    $ssh = "22";
  }  
}

# get ip if a hostname is set
sub get_ip 
{
	use Net::DNS;

	my ( $host_name ) = @_;

	my $res = Net::DNS::Resolver->new;
	my $query = $res->search($host_name);

	if ($query) {
		foreach my $rr ($query->answer) {
			next unless $rr->type eq "A";
			return $rr->address;
		}
	} 
	else 
	{	
          $plugin_nagios->nagios_exit( CRITICAL, "Unable to resolve host address");
	}
}
 
__END__