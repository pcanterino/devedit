#!C:/Programme/Perl/bin/perl.exe -w

#
# Dev-Editor 3.1
#
# Dev-Editor's main program
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2006-08-24
#
# Copyright (C) 1999-2000 Roland Bluethgen, Frank Schoenmann
# Copyright (C) 2003-2009 Patrick Canterino
# All Rights Reserved.
#
# This file can be distributed and/or modified under the terms of
# of the Artistic License 1.0 (see also the LICENSE file found at
# the top level of the Dev-Editor distribution).
#

use strict;
use CGI::Carp qw(fatalsToBrowser);

use vars qw($VERSION);
use lib 'modules';

use CGI;
use Config::DevEdit;

use Command;
use Output;
use Tool;

$VERSION = '3.2-dev';

# Path to configuration file
# Change if necessary!

use constant CONFIGFILE => 'devedit.conf';

# Read the configuration file

my $config = read_config(CONFIGFILE);
error_template($config->{'templates'}->{'error'}); # Yes, I'm lazy...

# Check if the root directory exists

abort($config->{'errors'}->{'no_root_dir'}) unless(-d $config->{'fileroot'} && not -l $config->{'fileroot'});

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
 my $path = $curdir.'/'.$newfile;

 # Extract file and directory name...

 my $file = file_name($path);
 my $dir  = upper_path($path);

 # ... check if the directory exists ...

 my $temp_path = clean_path($config->{'fileroot'}.'/'.$dir);

 unless(-d $temp_path && not -l $temp_path)
 {
  abort($config->{'errors'}->{'dir_not_exist'},'/');
 }

 # ... and check if the path is above the root directory

 unless(($new_physical,$new_virtual) = check_path($config->{'fileroot'},$dir))
 {
  abort($config->{'errors'}->{'create_above_root'},'/');
 }

 # Check if we have enough permissions to create a file
 # in this directory

 unless(-r $new_physical && -w $new_physical && -x $new_physical)
 {
  abort($config->{'errors'}->{'dir_no_create'},'/',{DIR => encode_html($new_virtual)});
 }

 # Create the physical and the virtual path

 $new_physical = File::Spec->canonpath($new_physical.'/'.$file);
 $new_virtual .= $file;

 # Check if accessing this file is forbidden

 if(is_forbidden_file($config->{'forbidden'},$new_virtual))
 {
  abort($config->{'errors'}->{'forbidden_file'},'/');
 }
}

# This check has to be performed first or abs_path() will be confused

my $temp_path = clean_path($config->{'fileroot'}.'/'.$file);

if(-e $temp_path || -l $temp_path)
{
 if(my ($physical,$virtual) = check_path($config->{'fileroot'},$file))
 {
  if(is_forbidden_file($config->{'forbidden'},$virtual))
  {
   abort($config->{'errors'}->{'forbidden_file'},'/');
  }
  else
  {
   # Create a hash containing data submitted by the user
   # (some other necessary information are also included)

   my %data = (physical     => $physical,
               virtual      => $virtual,
               new_physical => $new_physical,
               new_virtual  => $new_virtual,
               cgi          => $cgi,
               version      => $VERSION,
               configfile   => CONFIGFILE);

   # Execute the command...

   my $output = exec_command($command,\%data,$config);

   # ... and show its output

   print $$output;
  }
 }
 else
 {
  abort($config->{'errors'}->{'above_root'},'/');
 }
}
else
{
 abort($config->{'errors'}->{'not_found'},'/');
}

#
### End ###