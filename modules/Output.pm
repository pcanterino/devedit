package Output;

#
# Dev-Editor - Module Output
#
# HTML generating routines
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2003-12-13
#

use strict;

use vars qw(@EXPORT);

use CGI qw(header);
use HTML::Entities;
use Tool;

### Export ###

use base qw(Exporter);

@EXPORT = qw(htmlhead
             htmlfoot
             error
             abort
             error_in_use
             equal_url
             dir_link);

# htmlhead()
#
# Generate the head of a HTML document
# (a text/html HTTP header will also be created)
#
# Params: Title/heading
#
# Return: Head for the HTML document

sub htmlhead($)
{
 my $title = shift;

 my $html = header(-type => "text/html");

 $html .= <<END;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
"http://www.w3.org/TR/html4/loose.dtd">

<html>
<head>
<title>$title</title>
<meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
</head>
<body bgcolor="#FFFFFF" text="#000000" link="#0000FF" vlink="#800080" alink="#FF0000">

<h1>$title</h1>

END

 return $html;
}

# htmlfoot()
#
# Generate the foot of a HTML document
#
# Params: -nothing-
#
# Return: Foot for the HTML document

sub htmlfoot
{
 return "\n</body>\n</html>";
}

# error()
#
# Format an error message
#
# Params: 1. Error message
#         2. Virtual path to which a link should be displayed (optional)
#
# Return: Formatted message (Scalar Reference)

sub error($;$)
{
 my ($message,$path) = @_;

 my $output = htmlhead("Error");
 $output   .= "<p>$message</p>";

 if($path)
 {
  $path = encode_entities($path);

  $output .= "\n\n";
  $output .= "<p><a href=\"$ENV{'SCRIPT_NAME'}?command=show&file=$path\">Back to $path</a></p>";
 }

 $output .= htmlfoot;

 return \$output;
}

# abort()
#
# Print an error message and exit script
# ^^^^^
#
# Params: Error message

sub abort($)
{
 my $output = error(shift);
 print $$output;
 exit;
}

# error_in_use()
#
# Create a message, which shows, that a
# file is currently in use
#
# Params: File, which is in use
#
# Return: Formatted message (Scalar Reference)

sub error_in_use($)
{
 my $file = shift;

 return error("The file '".encode_entities($file)."' is currently edited by someone else.",upper_path($file));
}

# equal_url()
#
# Create an "equals"-link
#
# Params: 1. HTTP root
#         2. Relative path
#
# Return: Formatted link (String)

sub equal_url($$)
{
 my ($root,$path) = @_;
 my $url;

 $root =~ s!/$!!;
 $path =~ s!^/!!;
 $url  =  $root."/".$path;
 $url  =  encode_entities($url);

 return "<p>(equals <a href=\"$url\" target=\"_blank\">$url</a>)</p>\n\n";
}

# dir_link()
#
# Create the link to the directory of a file
#
# Params: File
#
# Return: Formatted link (String)

sub dir_link($)
{
 my $dir = upper_path(shift);
 $dir    = encode_entities($dir);

 return "<p><a href=\"$ENV{'SCRIPT_NAME'}?command=show&file=$dir\">Back to $dir</a></p>\n\n";
}

# it's true, baby ;-)

1;

#
### End ###