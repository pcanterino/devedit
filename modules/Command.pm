package Command;

#
# Dev-Editor - Module Command
#
# Execute Dev-Editor's commands
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 10-04-2003
#

use strict;

use vars qw(@EXPORT
            $script);

use CGI qw(redirect);

use File::Access;
use File::Copy;

use HTML::Entities;
use Output;
use POSIX qw(strftime);
use Tool;

$script = $ENV{'SCRIPT_NAME'};

### Export ###

use base qw(Exporter);

@EXPORT = qw(exec_show
             exec_beginedit
             exec_endedit
             exec_mkfile
             exec_mkdir
             exec_workwithfile
             exec_copy
             exec_rename
             exec_remove
             exec_unlock);

# exec_show()
#
# View a directory or a file
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_show($$$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $output;

 if(-d $physical)
 {
  # Create directory listing

  my $direntries = dir_read($physical);
  return error("Reading of directory $virtual failed") unless($direntries);

  my $files = $direntries->{'files'};
  my $dirs  = $direntries->{'dirs'};

  $output .= htmlhead("Directory listing of $virtual");
  $output .= equal_url($config->{'httproot'},$virtual);
  $output .= "<hr>\n\n<pre>\n";

  # Create the link to the upper directory
  # (only if we are not in the root directory)

  unless($virtual eq "/")
  {
   my $upper = $physical."/..";
   my @stat  = stat($upper);

   $output .= "  [SUBDIR]  ";
   $output .= strftime("%d.%m.%Y %H:%M",localtime($stat[9]));
   $output .= " " x 10;
   $output .= "<a href=\"$script?command=show&file=".encode_entities(upper_path($virtual))."\">../</a>\n";
  }

  # Get the length of the longest file/directory name

  my $max_name_len = 0;

  foreach(@$dirs,@$files)
  {
   my $length    = length($_);
   $max_name_len = $length if($length > $max_name_len);
  }

  # Directories

  foreach my $dir(@$dirs)
  {
   my @stat = stat($physical."/".$dir);

   $output .= "  ";
   $output .= "[SUBDIR]  ";
   $output .= strftime($config->{'timeformat'},localtime($stat[9]));
   $output .= " " x 10;
   $output .= "<a href=\"$script?command=show&file=".encode_entities($virtual.$dir)."/\">".encode_entities($dir)."/</a>\n";
  }

  # Files

  foreach my $file(@$files)
  {
   my $phys_path = $physical."/".$file; # Not exactly...
   my $virt_path = encode_entities($virtual.$file);

   my @stat      = stat($phys_path);
   my $in_use    = $data->{'uselist'}->in_use($virtual.$file);

   $output .= " " x (10 - length($stat[7]));
   $output .= $stat[7];
   $output .= "  ";
   $output .= strftime($config->{'timeformat'},localtime($stat[9]));
   $output .= ($in_use) ? " (IN USE) " : (not -T $phys_path) ? " (BINARY) " : " " x 10;
   $output .= encode_entities($file);
   $output .= " " x ($max_name_len - length($file))."\t  (";

   $output .= (-T $phys_path)
              ? "<a href=\"$script?command=show&file=$virt_path\">View</a>"
              : '<span style="color:#C0C0C0">View</span>';

   $output .= " | ";

   $output .= ($in_use || not -T $phys_path)
              ? '<span style="color:#C0C0C0">Edit</span>'
              : "<a href=\"$script?command=beginedit&file=$virt_path\">Edit</a>";

   $output .= " | <a href=\"$script?command=workwithfile&file=$virt_path\">Do other stuff</a>)\n";
  }

  $output .= "</pre>\n\n<hr>\n\n";

  # Bottom of directory listing
  # (Fields for creating files and directories)

  $output .= <<END;
<table border="0">
<tr>
<form action="$script">
<input type="hidden" name="command" value="mkdir">
<input type="hidden" name="curdir" value="$virtual">
<td>Create new directory:</td>
<td>$virtual <input type="text" name="newfile"> <input type="submit" value="Create!"></td>
</form>
</tr>
<tr>
<td>Create new file:</td>
<form action="$script">
<input type="hidden" name="command" value="mkfile">
<input type="hidden" name="curdir" value="$virtual">
<td>$virtual <input type="text" name="newfile"> <input type="submit" value="Create!"></td>
</form>
</tr>
</table>

<hr>
END
  $output .= htmlfoot;
 }
 else
 {
  # View a file

  # Check on binary files
  # We have to do it in this way, or empty files
  # will be recognized as binary files

  unless(-T $physical)
  {
   # Binary file

   return error("This editor is not able to view/edit binary files.");
  }
  else
  {
   # Text file

   $output  = htmlhead("Contents of file ".encode_entities($virtual));
   $output .= equal_url($config->{'httproot'},$virtual);
   $output .= dir_link($virtual);

   $output .= '<div style="background-color:#FFFFE0;border:1px solid black;margin-top:10px;width:100%">'."\n";
   $output .= '<pre style="color:#0000C0;">'."\n";
   $output .= encode_entities(${file_read($physical)});
   $output .= "\n</pre>\n</div>";

   $output .= htmlfoot;
  }
 }

 return \$output;
}

# exec_beginedit
#
# Lock a file and display a form to edit it
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_beginedit($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $uselist        = $data->{'uselist'};

 return error("You cannot edit directories.") if(-d $physical);
 return error_in_use($virtual) if($uselist->in_use($virtual));

 # Check on binary files

 unless(-T $physical)
 {
  # Binary file

  return error("This editor is not able to view/edit binary files.");
 }
 else
 {
  # Text file

  $uselist->add_file($virtual);
  $uselist->save;

  my $dir       = upper_path($virtual);
  my $content   = encode_entities(${file_read($physical)});

  my $equal_url = equal_url($config->{'httproot'},$virtual);

  $virtual   = encode_entities($virtual);

  my $output = htmlhead("Edit file $virtual");
  $output   .= $equal_url;
  $output   .= <<END;
<p><b style="color:#FF0000">Caution!</b> This file is locked for other users while you are editing it. To unlock it, click <i>Save and exit</i> or <i>Exit WITHOUT saving</i>. Please <b>don't</b> click the <i>Reload</i> button in your browser! This will confuse the editor.</p>

<form action="$script" method="get">
<input type="hidden" name="command" value="canceledit">
<input type="hidden" name="file" value="$virtual">
<p><input type="submit" value="Exit WITHOUT saving"></p>
</form>

<form action="$script" method="post">
<input type="hidden" name="command" value="endedit">
<input type="hidden" name="file" value="$virtual">

<table width="100%" border="1">
<tr>
<td width="50%" align="center">
<input type="hidden" name="file" value="$virtual">
<input type="checkbox" name="saveas" value="1"> Save as new file: $dir <input type=text name="newfile" value=""></td>
<td width="50%" align="center"><input type="checkbox" name="encode_iso" value="1"> Encode ISO-8859-1 special chars</td>
</tr>
<tr>
<td align="center"><input type="reset" value="Reset form"></td>
<td align="center"><input type="submit" value="Save and exit"></td>
</tr>
</table>

<textarea name="filecontent" rows="25" cols="120">$content</textarea>
</form>
END

  $output .= htmlfoot;

  return \$output;
 }
}

# exec_endedit()
#
# Save a file, unlock it and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_endedit($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $content        = $data->{'cgi'}->param('filecontent');

 return error("You cannot edit directories.") if(-d $physical);

 if($data->{'cgi'}->param('encode_iso'))
 {
  # Encode all ISO-8859-1 special chars

  $content = encode_entities($content,"\200-\377");
 }

 if($data->{'cgi'}->param('saveas'))
 {
  # Create the new filename

  $physical = $data->{'new_physical'};
  $virtual  = $data->{'new_virtual'};
 }

 if(file_save($physical,\$content))
 {
  # Saving of the file was successful - so unlock it!

  return exec_unlock($data,$config);
 }
 else
 {
  return error("Saving of file '".encode_entities($virtual)."' failed'.");
 }
}

# exec_mkfile()
#
# Create a file and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_mkfile($$)
{
 my ($data,$config) = @_;
 my $new_physical   = $data->{'new_physical'};
 my $new_virtual    = $data->{'new_virtual'};
 my $dir            = upper_path($new_virtual);
 $new_virtual       = encode_entities($new_virtual);

 return error("A file or directory called '$new_virtual' does already exist.") if(-e $new_physical);

 file_create($new_physical) or return error("Could not create file '$new_virtual'.");

 my $output = redirect("http://$ENV{'HTTP_HOST'}$script?command=show&file=$dir");
 return \$output;
}

# exec_mkdir()
#
# Create a directory and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_mkdir($$)
{
 my ($data,$config) = @_;
 my $new_physical   = $data->{'new_physical'};
 my $new_virtual    = $data->{'new_virtual'};
 my $dir            = upper_path($new_virtual);
 $new_virtual       = encode_entities($new_virtual);

 return error("A file or directory called '$new_virtual' does already exist.") if(-e $new_physical);

 mkdir($new_physical) or return error("Could not create directory '$new_virtual'.");

 my $output = redirect("http://$ENV{'HTTP_HOST'}$script?command=show&file=$dir");
 return \$output;
}

# exec_workwithfile()
#
# Display a form for renaming/copying/deleting/unlocking a file
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_workwithfile($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $unused         = $data->{'uselist'}->unused($virtual);

 my $dir = encode_entities(upper_path($virtual));

 my $output = htmlhead("Work with file ".encode_entities($virtual));
 $output   .= equal_url($config->{'httproot'},$virtual);

 $virtual   = encode_entities($virtual);

 $output   .= dir_link($virtual);
 $output   .= "<p><b>Note:</b> On UNIX systems, filenames are <b>case-sensitive</b>!</p>\n\n";

 $output .= "<p>Someone else is currently editing this file. So not all features are available.</p>\n\n" unless($unused);

 # Copying of the file as always allowed

 $output .= <<END;
<hr>

<h2>Copy</h2>

<form action="$script">
<input type="hidden" name="command" value="copy">
<input type="hidden" name="file" value="$virtual">
<p>Copy file '$virtual' to: $dir <input type="text" name="newfile" size="50"> <input type="submit" value="Copy!"></p>
</form>

<hr>

END

 if($unused)
 {
  # File is not locked
  # Allow renaming and deleting the file

  $output .= <<END;
<h2>Move/rename</h2>

<form action="$script">
<input type="hidden" name="command" value="rename">
<input type="hidden" name="file" value="$virtual">
<p>Move/Rename file '$virtual' to: $dir <input type="text" name="newfile" size="50"> <input type="submit" value="Move/Rename!"></p>
</form>

<hr>

<h2>Delete</h2>

<form action="$script" method="get">
<input type="hidden" name="file" value="$virtual">
<input type="hidden" name="command" value="remove">
<p><input type="submit" value="Delete file '$virtual'!"></p>
</form>
END
 }
 else
 {
  # File is locked
  # Just display a button for unlocking it

  $output .= <<END;
<h2>Unlock file</h2>

<p>Someone else is currently editing this file. At least, the file is marked so. Maybe, someone who was editing the file has forgotten to unlock it. In this case (and <b>only</b> in this case) you can unlock the file using this button:</p>

<form action="$script" method="get">
<input type="hidden" name="file" value="$virtual">
<input type="hidden" name="command" value="unlock">
<p><input type="submit" value="Unlock file '$virtual'"></p>
</form>
END
 }

 $output .= "\n<hr>";
 $output .= htmlfoot;

 return \$output;
}

# exec_copy()
#
# Copy a file and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_copy($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = encode_entities($data->{'virtual'});
 my $new_physical   = $data->{'new_physical'};
 my $new_virtual    = $data->{'new_virtual'};
 my $dir            = upper_path($new_virtual);
 $new_virtual       = encode_entities($new_virtual);

 return error("This editor is not able to copy directories.") if(-d $physical);

 if(-e $new_physical)
 {
  return error("A file or directory called '$new_virtual' does already exists and this editor is currently not able to ask to overwrite the existing file or directory.");
 }

 copy($physical,$new_physical) or return error("Could not copy '$virtual' to '$new_virtual'");

 my $output = redirect("http://$ENV{'HTTP_HOST'}$script?command=show&file=$dir");
 return \$output;
}

# exec_rename()
#
# Rename/move a file and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_rename($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $new_physical   = $data->{'new_physical'};
 my $new_virtual    = $data->{'new_virtual'};
 my $dir            = upper_path($new_virtual);
 $new_virtual       = encode_entities($new_virtual);

 return error_in_use($virtual) if($data->{'uselist'}->in_use($virtual));

 if(-e $new_physical)
 {
  return error("A file or directory called '$new_virtual' does already exists and this editor is currently not able to ask to overwrite the existing file or directory.");
 }

 rename($physical,$new_physical) or return error("Could not move/rename '".encode_entities($virtual)."' to '$new_virtual'.");

 my $output = redirect("http://$ENV{'HTTP_HOST'}$script?command=show&file=$dir");
 return \$output;
}

# exec_remove()
#
# Remove a file and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_remove($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};

 return error("Deleting directories is currently unsupported") if(-d $physical);
 return error_in_use($virtual) if($data->{'uselist'}->in_use($virtual));

 unlink($physical) or return error("Could not delete file '".encode_entities($virtual)."'.");

 my $output = redirect("http://$ENV{'HTTP_HOST'}$script?command=show&file=".upper_path($virtual));
 return \$output;
}

# exec_unlock()
#
# Remove a file from the list of used files and
# return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_unlock($$)
{
 my ($data,$config) = @_;
 my $virtual        = $data->{'virtual'};
 my $uselist        = $data->{'uselist'};

 $uselist->remove_file($virtual);
 $uselist->save;

 my $output = redirect("http://$ENV{'HTTP_HOST'}$script?command=show&file=".upper_path($virtual));
 return \$output;
}

# it's true, baby ;-)

1;

#
### End ###