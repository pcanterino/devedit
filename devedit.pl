#!C:/Programme/Perl/bin/perl.exe -w

#
# Dev-Editor 2.1a
#
# Dev-Editor's main program
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2004-10-04
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

$VERSION = '2.1a';

# Path to configuration file
# Change if necessary!

use constant CONFIGFILE => 'devedit.dat';

# Read the configuration file

my $config = read_config(CONFIGFILE);
error_template($config->{'templates'}->{'error'}); # Yes, I'm lazy...

# Read the most important form data

my $cgi = new CGI;

my $command = $cgi->param('command') || 'show';
my $file    = $cgi->param('file')    || '/';
my $curdir  = $cgi->param('curdir')  || '';
my $newfile = $cgi->param('newfile') || '';

# Create physical and virtual path for the new file
# This section has to be optimized - ugh!

my $new_physical = '';
my $new_virtual  = '';

if($newfile ne '' && $newfile !~ /^\s+$/)
{
 $curdir  = upper_path($file) if($curdir eq '');
 my $path = clean_path($curdir.$newfile);

 # Extract file and directory name...

 my $file = file_name($path);
 my $dir  = upper_path($path);

 # ... check if the directory exists ...

 unless(-d clean_path($config->{'fileroot'}."/".$dir))
 {
  abort($config->{'errors'}->{'dir_not_exist'});
 }

 # ... and check if the path is above the root directory

 unless(($new_physical,$new_virtual) = check_path($config->{'fileroot'},$dir))
 {
  abort($config->{'errors'}->{'create_ar'});
 }

 # Create the physical and the virtual path

 $new_physical = File::Spec->canonpath($new_physical."/".$file);
 $new_virtual .= $file;
}

# This check has to be performed first or abs_path() will be confused

if(-e clean_path($config->{'fileroot'}."/".$file))
{
 if(my ($physical,$virtual) = check_path($config->{'fileroot'},$file))
 {
  # Create a File::UseList object and load the list

  my $uselist = new File::UseList(listfile => $config->{'uselist_file'},
                                  lockfile => $config->{'lock_file'},
                                  timeout  => $config->{'lock_timeout'});

  $uselist->lock or abort($config->{'errors'}->{'lock_failed'},{USELIST => $config->{'uselist_file'}, LOCK_FILE => $config->{'lock_file'}});
  $uselist->load;

  # Create a hash with data submitted by user
  # (some other necessary information will also be included)

  my %data = (physical     => $physical,
              virtual      => $virtual,
              new_physical => $new_physical,
              new_virtual  => $new_virtual,
              uselist      => $uselist,
              cgi          => $cgi,
              version      => $VERSION,
              configfile   => CONFIGFILE);

  my $output = exec_command($command,\%data,$config); # Execute the command...

  $uselist->unlock; # ... unlock the list with files in use...
  print $$output;   # ... and show the output of the command
 }
 else
 {
  abort($config->{'errors'}->{'above_root'});
 }
}
else
{
 abort($config->{'errors'}->{'not_exist'});
}

#
### End ###