package File::Access;

#
# Dev-Editor - Module File::Access
#
# Some simple routines for doing things with files by
# using only one command
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2005-08-01
#

use strict;

use vars qw(@EXPORT
            $has_flock);

use Fcntl qw(:DEFAULT
             :flock);

use File::Copy;

### Export ###

use base qw(Exporter);

@EXPORT = qw(dir_copy
             dir_read
             file_create
             file_lock
             file_read
             file_save

             LOCK_SH
             LOCK_EX
             LOCK_UN
             LOCK_NB);

# Check if flock() is available
# I found this piece of code somewhere in the internet

$has_flock = eval { local $SIG{'__DIE__'}; flock(STDOUT,0); 1 };

# Predeclaration of dir_copy()

sub dir_copy($$);

# dir_copy()
#
# Copy a directory
#
# Params: 1. Directory to copy
#         2. Target
#
# Return: Status code (Boolean)

sub dir_copy($$)
{
 my ($dir,$target) = @_;

 return unless(-d $dir);

 my $entries = dir_read($dir) or return;

 my $dirs    = $entries->{'dirs'};
 my $files   = $entries->{'files'};

 mkdir($target,0777) unless(-d $target);

 foreach my $directory(@$dirs)
 {
  unless(-d $target.'/'.$directory)
  {
   mkdir($target.'/'.$directory,0777) or next;
  }

  if(-r $target.'/'.$directory && -x $target.'/'.$directory)
  {
   dir_copy($dir.'/'.$directory,$target.'/'.$directory) or next;
  }
 }

 foreach my $file(@$files)
 {
  copy($dir.'/'.$file,$target.'/'.$file) or next;
 }

 return 1;
}

# dir_read()
#
# Collect the files and directories in a directory
#
# Params: Directory
#
# Return: Hash reference: dirs  => directories
#                         files => files and symbolic links

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
  next if($entry eq '.' || $entry eq '..');

  if(-d $dir.'/'.$entry && not -l $dir.'/'.$entry)
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
# Create a file, but only if it doesn't already exist
#
# (I wanted to use O_EXCL for this, but `perldoc -f sysopen`
# doesn't say that it is available on every system - so I
# created this workaround using O_RDONLY and O_CREAT)
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

 sysopen(FILE,$file,O_RDONLY | O_CREAT) or return;
 close(FILE)                            or return;

 return 1;
}

# file_lock()
#
# System independent wrapper function for flock()
# On systems where flock() is not available, this function
# always returns true.
#
# Params: 1. Filehandle
#         2. Locking mode
#
# Return: Status code (Boolean)

sub file_lock(*$)
{
 my ($handle,$mode) = @_;

 return 1 unless($has_flock);
 return flock($handle,$mode);
}

# file_read()
#
# Read out a file completely
#
# Params: 1. File
#         2. true  => open in binary mode
#            false => open in normal mode (default)
#
# Return: Contents of the file (Scalar Reference)

sub file_read($;$)
{
 my ($file,$binary) = @_;
 local *FILE;

 sysopen(FILE,$file,O_RDONLY) or return;
 file_lock(FILE,LOCK_SH)      or do { close(FILE); return };
 binmode(FILE) if($binary);

 read(FILE, my $content, -s $file);

 close(FILE)                  or return;

 return \$content;
}

# file_save()
#
# Save a file
#
# Params: 1. File
#         2. File content as Scalar Reference
#         3. true  => open in binary mode
#            false => open in normal mode (default)
#
# Return: Status code (Boolean)

sub file_save($$;$)
{
 my ($file,$content,$binary) = @_;
 local *FILE;

 sysopen(FILE,$file,O_WRONLY | O_CREAT | O_TRUNC) or return;
 file_lock(FILE,LOCK_EX)                          or do { close(FILE); return };
 binmode(FILE) if($binary);

 print FILE $$content                             or do { close(FILE); return };

 close(FILE)                                      or return;

 return 1;
}

# it's true, baby ;-)

1;

#
### End ###