#!C:/Programme/Perl/bin/perl.exe -w

#
# Dev-Editor 2.3.1
#
# Dev-Editor's main program
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2005-02-13
#

use strict;
use CGI::Carp qw(fatalsToBrowser);

use vars qw($VERSION);
use lib 'modules';

use CGI;
use Config::DevEdit;
use File::UseList;

use Command;
use Output;
use Tool;

$VERSION = '2.3.1';

# Path to configuration file
# Change if necessary!

use constant CONFIGFILE => 'devedit.dat';

# Read the configuration file

my $config = read_config(CONFIGFILE);
error_template($config->{'templates'}->{'error'}); # Yes, I'm lazy...

# Check if the root directory exists

abort($config->{'errors'}->{'no_root_dir'}) unless(-d $config->{'fileroot'});

# Check if we are able to access the root directory

abort($config->{'errors'}->{'no_root_access'}) unless(-r $config->{'fileroot'} && -x $config->{'fileroot'});

# Read the most important form data

my $cgi = new CGI;

my $command = $cgi->param('command') || 'show';
my $file    = $cgi->param('file')    || '/';
my $curdir  = $cgi->param('curdir')  || '';
my $newfile = $cgi->param('newfile') || '';

# Create physical and virtual path for the new file

my $new_physical = '';
my $new_virtual  = '';

if($newfile ne '' && $newfile !~ /^\s+$/)
{
 $curdir  = upper_path($file) if($curdir eq '');
 my $path = $curdir.'/'.$newfile;

 # Extract file and directory name...

 my $file = file_name($path);
 my $dir  = upper_path($path);

 # ... check if the directory exists ...

 unless(-d clean_path($config->{'fileroot'}.'/'.$dir) && not -l clean_path($config->{'fileroot'}.'/'.$dir))
 {
  abort($config->{'errors'}->{'dir_not_exist'},'/');
 }

 # ... and check if the path is above the root directory

 unless(($new_physical,$new_virtual) = check_path($config->{'fileroot'},$dir))
 {
  abort($config->{'errors'}->{'create_ar'},'/');
 }

 # Check if we have enough permissions to create a file
 # in this directory

 unless(-r $new_physical && -w $new_physical && -x $new_physical)
 {
  abort($config->{'errors'}->{'dir_no_create'},'/',{DIR => $new_virtual});
 }

 # Create the physical and the virtual path

 $new_physical = File::Spec->canonpath($new_physical.'/'.$file);
 $new_virtual .= $file;
}

# This check has to be performed first or abs_path() will be confused

if(-e clean_path($config->{'fileroot'}.'/'.$file) || -l clean_path($config->{'fileroot'}.'/'.$file))
{
 if(my ($physical,$virtual) = check_path($config->{'fileroot'},$file))
 {
  # Create a File::UseList object and load the list

  my $uselist = new File::UseList(listfile => $config->{'uselist_file'},
                                  lockfile => $config->{'lock_file'},
                                  timeout  => $config->{'lock_timeout'});

  $uselist->lock or abort($config->{'errors'}->{'lock_failed'},undef,{USELIST => $uselist->{'listfile'}, LOCK_FILE => $uselist->{'lockfile'}});
  $uselist->load;

  # Create a hash containing data submitted by the user
  # (some other necessary information are also included)

  my %data = (physical     => $physical,
              virtual      => $virtual,
              new_physical => $new_physical,
              new_virtual  => $new_virtual,
              uselist      => $uselist,
              cgi          => $cgi,
              version      => $VERSION,
              configfile   => CONFIGFILE);

  # Execute the command...

  my $output = exec_command($command,\%data,$config);

  # ... unlock the list with files in use and show the output of the command

  $uselist->unlock or abort($config->{'errors'}->{'unlock_failed'},undef,{USELIST => $uselist->{'listfile'}, LOCK_FILE => $uselist->{'lockfile'}});
  print $$output;
 }
 else
 {
  abort($config->{'errors'}->{'above_root'},'/');
 }
}
else
{
 abort($config->{'errors'}->{'not_exist'},'/');
}

#
### End ###