#!C:/Programme/Perl/bin/perl.exe -w

#
# Dev-Editor 1.2
#
# Dev-Editor's main program
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2003-12-02
#

use strict;
use CGI::Carp qw(fatalsToBrowser);

use vars qw(%config);

use lib 'modules';

use CGI;
use Command;
use File::UseList;
use Output;
use Tool;

### Settings ###

%config = (
           fileroot     => 'D:/Server/WWW/dokumente/devedit-test',
           httproot     => '/devedit-test/',
           timeformat   => '%d.%m.%Y %H:%M',
           uselist_file => 'uselist',
           lock_file    => 'uselist.lock',
           lock_timeout => '10'
          );

### End Settings ###

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

if($newfile ne '')
{
 $curdir  = upper_path($file) if($curdir eq '');
 my $path = clean_path($curdir.$newfile);

 # Extract file and directory name...

 my $file = file_name($path);
 my $dir  = upper_path($path);

 # ... check if the directory exists ...

 unless(-d clean_path($config{'fileroot'}."/".$dir))
 {
  abort("The directory where you want to create this file or directory doesn't exist.");
 }

 # ... and check if the path is above the root directory

 unless(($new_physical,$new_virtual) = check_path($config{'fileroot'},$dir))
 {
  abort("You aren't allowed to create files and directories above the virtual root directory.");
 }

 # Create the physical and the virtual path

 $new_physical = File::Spec->canonpath($new_physical."/".$file);
 $new_virtual .= $file;
}

# This check has to be performed first, or abs_path() will be confused

if(-e clean_path($config{'fileroot'}."/".$file))
{
 if(my ($physical,$virtual) = check_path($config{'fileroot'},$file))
 {
  # Create a File::UseList object and load the list

  my $uselist = new File::UseList(listfile => $config{'uselist_file'},
                                  lockfile => $config{'lock_file'},
                                  timeout  => $config{'lock_timeout'});

  $uselist->lock or abort("Locking of $config{'uselist_file'} failed. Try it again in a moment. If the problem persists, ask someone to recreate the lock file ($config{'lock_file'}).");
  $uselist->load;

  # Create a hash with data submitted by user
  # (the CGI and the File::UseList object will also be included)

  my %data = (physical     => $physical,
              virtual      => $virtual,
              new_physical => $new_physical,
              new_virtual  => $new_virtual,
              uselist      => $uselist,
              cgi          => $cgi);

  my $output = exec_command($command,\%data,\%config); # Execute the command...

  $uselist->unlock; # ... unlock the list with files in use...
  print $$output;   # ... and print the output of the command
 }
 else
 {
  abort("Accessing files and directories above the virtual root directory is forbidden.");
 }
}
else
{
 abort("File/directory does not exist.");
}

#
### End ###