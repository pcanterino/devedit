package Tool;

#
# Dev-Editor - Module Tool
#
# Some shared sub routines
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2005-07-23
#

use strict;

use vars qw(@EXPORT);

use CGI qw(redirect
           escape
           virtual_host
           https);

use Cwd qw(abs_path);
use File::Spec;

### Export ###

use base qw(Exporter);

@EXPORT = qw(check_path
             clean_path
             devedit_reload
             dos_wildcard_match
             encode_html
             equal_url
             file_name
             is_forbidden_file
             mode_string
             multi_string
             upper_path);

# check_path()
#
# Check if a virtual path is above a virtual root directory
# (currently no check if the path exists - check otherwise!)
#
# Params: 1. Virtual root directory
#         2. Virtual path to check
#
# Return: Array with the physical and the cleaned virtual path;
#         false, if the submitted path is above the root directory

sub check_path($$)
{
 my ($root,$path) = @_;

 # Clean root path

 $root = abs_path($root);
 $root = File::Spec->canonpath($root);

 $path =~ tr!\\!/!;
 $path =~ s!^/+!!;
 $path =  $root.'/'.$path;

 # We extract the last part of the path and create the absolute path

 my $first = upper_path($path);
 $first    = File::Spec->canonpath($first);
 $first    = abs_path($first);

 my $last  = file_name($path);

 if(-d $first.'/'.$last && (not -l $first.'/'.$last) && -r $first.'/'.$last && -x $first.'/'.$last)
 {
  $first = abs_path($first.'/'.$last);
  $last  = '';
 }

 $path = File::Spec->canonpath($first.'/'.$last);

 # Check if the path is above the root directory

 return if(index($path,$root) != 0);

 # Create short path name

 my $short_path = substr($path,length($root));
 $short_path =~ tr!\\!/!;
 $short_path = '/'.$short_path if($short_path !~ m!^/!);
 $short_path = $short_path.'/' if($short_path !~ m!/$! && -d $path && not -l $path);

 return ($path,$short_path);
}

# clean_path()
#
# Clean up a path logically and replace backslashes with
# normal slashes
#
# Params: Path
#
# Return: Cleaned path

sub clean_path($)
{
 my $path =  shift;
 $path    =  File::Spec->canonpath($path);
 $path    =~ tr!\\!/!;

 return $path;
}

# devedit_reload()
#
# Create a HTTP redirection header to load Dev-Editor
# with some other parameters
#
# Params: Hash Reference (will be merged to a query string)
#         (optional)
#
# Return: HTTP redirection header (Scalar Reference)

sub devedit_reload(;$)
{
 my $params = shift;

 # Detect the protocol (simple HTTP or SSL encrypted HTTP)
 # and check if the server listens on the default port

 my $protocol = '';
 my $port     = '';

 if(https)
 {
  # SSL encrypted HTTP (HTTPS)

  $protocol = 'https';
  $port     = ':'.$ENV{'SERVER_PORT'} if($ENV{'SERVER_PORT'} != 443);
 }
 else
 {
  # Simple HTTP

  $protocol = 'http';
  $port     = ':'.$ENV{'SERVER_PORT'} if($ENV{'SERVER_PORT'} != 80);
 }

 # The following code is grabbed from Template::_query of
 # Andre Malo's selfforum (http://sourceforge.net/projects/selfforum/)
 # and modified by Patrick Canterino

 my $query = '';

 if(ref($params) eq 'HASH')
 {
  $query = '?'.join ('&' =>
    map {
      (ref)
      ? map{escape ($_).'='.escape ($params -> {$_})} @{$params -> {$_}}
      : escape ($_).'='.escape ($params -> {$_})
    } keys %$params
  );
 }

 # Create the redirection header

 my $header = redirect($protocol.'://'.virtual_host.$port.$ENV{'SCRIPT_NAME'}.$query);

 return \$header;
}

# dos_wildcard_match()
#
# Check if a string matches against a DOS-style wildcard
#
# Params: 1. Pattern
#         2. String
#
# Return: Status code (Boolean)

sub dos_wildcard_match($$)
{
 my ($pattern,$string) = @_;

 # The following part is stolen from File::DosGlob

 # escape regex metachars but not glob chars
 $pattern =~ s:([].+^\-\${}[|]):\\$1:g;
 # and convert DOS-style wildcards to regex
 $pattern =~ s/\*/.*/g;
 $pattern =~ s/\?/.?/g;

 return ($string =~ m|^$pattern$|is);
}

# encode_html()
#
# Encode HTML control characters (< > " &)
#
# Params: String to encode
#
# Return: Encoded string

sub encode_html($)
{
 my $string = shift;

 $string =~ s/&/&amp;/g;
 $string =~ s/</&lt;/g;
 $string =~ s/>/&gt;/g;
 $string =~ s/"/&quot;/g;

 return $string;
}

# equal_url()
#
# Create URL equal to a file or directory
#
# Params: 1. HTTP root
#         2. Relative path
#
# Return: Formatted link (String)

sub equal_url($$)
{
 my ($root,$path) = @_;
 my $url;

 $root =~ s!/+$!!;
 $path =~ s!^/+!!;
 $url  =  $root.'/'.$path;

 return $url;
}

# file_name()
#
# Return the last part of a path
#
# Params: Path
#
# Return: Last part of the path

sub file_name($)
{
 my $path =  shift;
 $path    =~ tr!\\!/!;

 unless($path =~ m!^/+$! || ($^O eq 'MSWin32' && $path =~ m!^[a-z]:/+$!i))
 {
  $path =~ s!/+$!!;
  $path =  substr($path,rindex($path,'/')+1);
 }

 return $path;
}

# is_forbidden_file()
#
# Check if a file is in the list of forbidden files
#
# Params: 1. Array Reference containing the list
#         2. Filename to check
#
# Return: Status code (Boolean)

sub is_forbidden_file($$)
{
 my ($list,$file) = @_;
 $file =~ s!/+$!!g;

 foreach my $entry(@$list)
 {
  return 1 if($file eq $entry);
  return 1 if(index($file,$entry.'/') == 0);
 }

 return;
}

# mode_string()
#
# Convert a file mode number into a human readable string (rwxr-x-r-x)
# (also supports SetUID, SetGID and Sticky Bit)
#
# Params: File mode number
#
# Return: Human readable mode string

sub mode_string($)
{
 my $mode   = shift;
 my $string = '';

 # User

 $string  = ($mode & 00400) ? 'r' : '-';
 $string .= ($mode & 00200) ? 'w' : '-';
 $string .= ($mode & 00100) ? (($mode & 04000) ? 's' : 'x') :
                               ($mode & 04000) ? 'S' : '-';

 # Group

 $string .= ($mode & 00040) ? 'r' : '-';
 $string .= ($mode & 00020) ? 'w' : '-';
 $string .= ($mode & 00010) ? (($mode & 02000) ? 's' : 'x') :
                               ($mode & 02000) ? 'S' : '-';

 # Other

 $string .= ($mode & 00004) ? 'r' : '-';
 $string .= ($mode & 00002) ? 'w' : '-';
 $string .= ($mode & 00001) ? (($mode & 01000) ? 't' : 'x') :
                               ($mode & 01000) ? 'T' : '-';

 return $string;
}

# multi_string()
#
# Create a Hash Reference containing three forms of a string
#
# Params: String
#
# Return: Hash Reference:
#         normal => Normal form of the string
#         html   => HTML encoded form (see encode_html())
#         url    => URL encoded form

sub multi_string($)
{
 my $string = shift;
 my %multi;

 $multi{'normal'} = $string;
 $multi{'html'}   = encode_html($string);
 $multi{'url'}    = escape($string);

 return \%multi;
}

# upper_path()
#
# Remove the last part of a path
# (the resulting path contains a trailing slash)
#
# Params: Path
#
# Return: Truncated path

sub upper_path($)
{
 my $path =  shift;
 $path    =~ tr!\\!/!;

 unless($path =~ m!^/+$! || ($^O eq 'MSWin32' && $path =~ m!^[a-z]:/+$!i))
 {
  $path =~ s!/+$!!;
  $path =  substr($path,0,rindex($path,'/')+1);
 }

 return $path;
}

# it's true, baby ;-)

1;

#
### End ###