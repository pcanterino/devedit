package File::Access;

#
# Dev-Editor - Module File::Access
#
# Some simple routines for doing things with files
# with only one command
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2004-07-21
#

use strict;

use vars qw(@EXPORT);

use Carp qw(croak);

### Export ###

use base qw(Exporter);

@EXPORT = qw(dir_read
             file_create
             file_read
             file_save
             file_unlock);

# dir_read()
#
# Collect the files and directories in a directory
#
# Params: Directory
#
# Return: Hash reference: dirs  => directories
#                         files => files

sub dir_read($)
{
 my $dir = shift;
 local *DIR;

 return unless(-d $dir);

 # Get all the entries in the directory

 opendir(DIR,$dir) or return;
 my @entries = readdir(DIR);
 closedir(DIR) or return;

 # Sort the entries

 @entries = sort {uc($a) cmp uc($b)} @entries;

 my @files;
 my @dirs;

 foreach my $entry(@entries)
 {
  next if($entry eq "." || $entry eq "..");

  if(-d $dir."/".$entry)
  {
   push(@dirs,$entry);
  }
  else
  {
   push(@files,$entry);
  }
 }

 return {dirs => \@dirs, files => \@files};
}

# file_create()
#
# Create a file
#
# Params: File to create
#
# Return: true on success;
#         false on error or if the file already exists

sub file_create($)
{
 my $file = shift;
 local *FILE;

 return if(-e $file);

 open(FILE,">$file") or return;
 close(FILE)         or return;

 return 1;
}

# file_read()
#
# Read out a file completely
#
# Params: File
#
# Return: Contents of the file (Scalar Reference)

sub file_read($)
{
 my $file = shift;
 local *FILE;

 open(FILE,"<$file") or return;
 read(FILE, my $content, -s $file);
 close(FILE)         or return;

 return \$content;
}

# file_save()
#
# Save a file
#
# Params: 1. File
#         2. File content as Scalar Reference
#
# Return: Status code (Boolean)

sub file_save($$)
{
 my ($file,$content) = @_;
 local *FILE;

 open(FILE,">$file")  or return;
 print FILE $$content or do { close(FILE); return };
 close(FILE)          or return;

 return 1;
}

# file_unlock()
#
# Remove a file from the list of files in use
#
# Params: 1. File::UseList object
#         2. File to remove
#
# Return: -nothing-

sub file_unlock($$)
{
 my ($uselist,$file) = @_;

 $uselist->remove_file($file);
 $uselist->save;

 return;
}

# it's true, baby ;-)

1;

#
### End ###