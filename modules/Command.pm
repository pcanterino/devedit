package Command;

#
# Dev-Editor - Module Command
#
# Execute Dev-Editor's commands
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2003-12-21
#

use strict;

use vars qw(@EXPORT);

use File::Access;
use File::Copy;
use File::Path;

use HTML::Entities;
use Output;
use POSIX qw(strftime);
use Tool;

my $script = $ENV{'SCRIPT_NAME'};

my %dispatch = ('show'         => \&exec_show,
                'beginedit'    => \&exec_beginedit,
                'canceledit'   => \&exec_unlock,
                'endedit'      => \&exec_endedit,
                'mkdir'        => \&exec_mkdir,
                'mkfile'       => \&exec_mkfile,
                'workwithfile' => \&exec_workwithfile,
                'workwithdir'  => \&exec_workwithdir,
                'copy'         => \&exec_copy,
                'rename'       => \&exec_rename,
                'remove'       => \&exec_remove,
                'rmdir'        => \&exec_rmdir,
                'unlock'       => \&exec_unlock
               );

### Export ###

use base qw(Exporter);

@EXPORT = qw(exec_command);

# exec_command()
#
# Execute the specified command
#
# Params: 1. Command to execute
#         2. Reference to user input hash
#         3. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_command($$$)
{
 my ($command,$data,$config) = @_;

 return error("Unknown command: $command") unless($dispatch{$command});

 my $output = &{$dispatch{$command}}($data,$config);
 return $output;
}

# exec_show()
#
# View a directory or a file
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_show($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $output;

 if(-d $physical)
 {
  # Create directory listing

  my $direntries = dir_read($physical);
  return error("Reading of directory $virtual failed.",upper_path($virtual)) unless($direntries);

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
   my @stat      = stat($physical."/".$dir);
   my $virt_path = encode_entities($virtual.$dir."/");

   $output .= "  ";
   $output .= "[SUBDIR]  ";
   $output .= strftime($config->{'timeformat'},localtime($stat[9]));
   $output .= " " x 10;
   $output .= "<a href=\"$script?command=show&file=$virt_path\">".encode_entities($dir)."/</a>";
   $output .= " " x ($max_name_len - length($dir) - 1)."\t  (";
   $output .= "<a href=\"$script?command=workwithdir&file=$virt_path\">Work with directory</a>)\n";
  }

  # Files

  foreach my $file(@$files)
  {
   my $phys_path = $physical."/".$file;
   my $virt_path = encode_entities($virtual.$file);

   my @stat      = stat($phys_path);
   my $in_use    = $data->{'uselist'}->in_use($virtual.$file);

   $output .= " " x (10 - length($stat[7]));
   $output .= $stat[7];
   $output .= "  ";
   $output .= strftime($config->{'timeformat'},localtime($stat[9]));
   $output .= " " x 10;
   $output .= encode_entities($file);
   $output .= " " x ($max_name_len - length($file))."\t  (";

   # Link "View"

   if(-r $phys_path && -T $phys_path)
   {
    $output .= "<a href=\"$script?command=show&file=$virt_path\">View</a>";
   }
   else
   {
    $output .= '<span style="color:#C0C0C0" title="';

    $output .= (not -r $phys_path) ? "Not readable" :
               (-B     $phys_path) ? "Binary file"  : "";

    $output .= '">View</span>';
   }

   $output .= " | ";

   # Link "Edit"

   if(-w $phys_path && -r $phys_path && -T $phys_path && not $in_use)
   {
    $output .= "<a href=\"$script?command=beginedit&file=$virt_path\">Edit</a>";
   }
   else
   {
    $output .= '<span style="color:#C0C0C0" title="';

    $output .= (not -r $phys_path) ? "Not readable" :
               (not -w $phys_path) ? "Read only"    :
               (-B     $phys_path) ? "Binary file"  :
               ($in_use)           ? "In use"       : "";

    $output .= '">Edit</span>';
   }

   # Link "Do other stuff"

   $output .= " | <a href=\"$script?command=workwithfile&file=$virt_path\">Work with file</a>)\n";
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

  return error("You have not enough permissions to view this file.",upper_path($virtual)) unless(-r $physical);

  # Check on binary files
  # We have to do it in this way, or empty files
  # will be recognized as binary files

  unless(-T $physical)
  {
   # Binary file

   return error("This editor is not able to view/edit binary files.",upper_path($virtual));
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

 return error("You cannot edit directories.",upper_path($virtual)) if(-d $physical);
 return error_in_use($virtual) if($uselist->in_use($virtual));
 return error("You have not enough permissions to edit this file.",upper_path($virtual)) unless(-r $physical && -w $physical);

 # Check on binary files

 unless(-T $physical)
 {
  # Binary file

  return error("This editor is not able to view/edit binary files.",upper_path($virtual));
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
 return error("You have not enough permissions to edit this file.",upper_path($virtual)) unless(-r $physical && -w $physical);

 # Normalize newlines

 $content =~ s/\015\012|\012|\015/\n/g;

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
  return error("Saving of file '".encode_entities($virtual)."' failed'. The file could be damaged, please check it's integrity.",upper_path($virtual));
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

 return error("A file or directory called '$new_virtual' already exists.",$dir) if(-e $new_physical);

 file_create($new_physical) or return error("Could not create file '$new_virtual'.",$dir);
 return devedit_reload({command => 'show', file => $dir});
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

 return error("A file or directory called '$new_virtual' already exists.",$dir) if(-e $new_physical);

 mkdir($new_physical,0777) or return error("Could not create directory '$new_virtual'.",$dir);
 return devedit_reload({command => 'show', file => $dir});
}

# exec_workwithfile()
#
# Display a form for renaming/copying/removing/unlocking a file
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

 $output .= "<hr>\n\n";

 # Copying of the file is always allowed - but we need read access

 if(-r $physical)
 {
  $output .= <<END;
<h2>Copy</h2>

<form action="$script">
<input type="hidden" name="command" value="copy">
<input type="hidden" name="file" value="$virtual">
<p>Copy file '$virtual' to:<br>$dir <input type="text" name="newfile" size="30"> <input type="submit" value="Copy!"></p>
</form>

<hr>

END
 }

 if($unused)
 {
  # File is not locked
  # Allow renaming and deleting the file

  $output .= <<END;
<h2>Move/rename</h2>

<form action="$script">
<input type="hidden" name="command" value="rename">
<input type="hidden" name="file" value="$virtual">
<p>Move/Rename file '$virtual' to:<br>$dir <input type="text" name="newfile" size="30"> <input type="submit" value="Move/Rename!"></p>
</form>

<hr>

<h2>Remove</h2>

<p>Click on the button below to remove the file '$virtual'.</p>

<form action="$script" method="get">
<input type="hidden" name="file" value="$virtual">
<input type="hidden" name="command" value="remove">
<p><input type="submit" value="Remove!"></p>
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

# exec_workwithdir()
#
# Display a form for renaming/removing a directory
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_workwithdir($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};

 my $dir = encode_entities(upper_path($virtual));

 my $output = htmlhead("Work with directory ".encode_entities($virtual));
 $output   .= equal_url($config->{'httproot'},$virtual);

 $virtual   = encode_entities($virtual);

 $output   .= dir_link($virtual);
 $output   .= "<p><b>Note:</b> On UNIX systems, filenames are <b>case-sensitive</b>!</p>\n\n";
 $output .= "<hr>\n\n";

 $output .= <<END;
<h2>Move/rename</h2>

<form action="$script">
<input type="hidden" name="command" value="rename">
<input type="hidden" name="file" value="$virtual">
<p>Move/Rename directory '$virtual' to:<br>$dir <input type="text" name="newfile" size="50"> <input type="submit" value="Move/Rename!"></p>
</form>

<hr>

<h2>Remove</h2>

<p>Click on the button below to completely remove the directory '$virtual' and oll of it's files and sub directories.</p>

<form action="$script" method="get">
<input type="hidden" name="file" value="$virtual">
<input type="hidden" name="command" value="rmdir">
<p><input type="submit" value="Remove!"></p>
</form>
END

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
 return error("You have not enough permissions to copy this file.") unless(-r $physical);

 if(-e $new_physical)
 {
  if(-d $new_physical)
  {
   return error("A directory called '$new_virtual' already exists. You cannot replace a directory by a file!",$dir);
  }
  elsif(not $data->{'cgi'}->param('confirmed'))
  {
   $dir = encode_entities($dir);

   my $output = htmlhead("Replace existing file");
   $output   .= <<"END";
<p>A file called '$new_virtual' already exists. Do you want to replace it?</p>

<form action="$script" method="get">
<input type="hidden" name="command" value="copy">
<input type="hidden" name="file" value="$virtual">
<input type="hidden" name="newfile" value="$new_virtual">
<input type="hidden" name="confirmed" value="1">

<p><input type="submit" value="Yes"></p>
</form>

<form action="$script" method="get">
<input type="hidden" name="command" value="show">
<input type="hidden" name="file" value="$dir">

<p><input type="submit" value="No"></p>
</form>
END

   $output .= htmlfoot;

   return \$output;
  }
 }

 if($data->{'uselist'}->in_use($data->{'new_virtual'}))
 {
  return error("The target file '$new_virtual' already exists and it is edited by someone else.",$dir);
 }

 copy($physical,$new_physical) or return error("Could not copy '$virtual' to '$new_virtual'",upper_path($virtual));
 return devedit_reload({command => 'show', file => $dir});
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
  if(-d $new_physical)
  {
   return error("A directory called '$new_virtual' already exists. You cannot replace a directory!",upper_path($virtual));
  }
  elsif(not $data->{'cgi'}->param('confirmed'))
  {
   $dir = encode_entities($dir);

   my $output = htmlhead("Replace existing file");
   $output   .= <<"END";
<p>A file called '$new_virtual' already exists. Do you want to replace it?</p>

<form action="$script" method="get">
<input type="hidden" name="command" value="rename">
<input type="hidden" name="file" value="$virtual">
<input type="hidden" name="newfile" value="$new_virtual">
<input type="hidden" name="confirmed" value="1">

<p><input type="submit" value="Yes"></p>
</form>

<form action="$script" method="get">
<input type="hidden" name="command" value="show">
<input type="hidden" name="file" value="$dir">

<p><input type="submit" value="No"></p>
</form>
END

   $output .= htmlfoot;

   return \$output;
  }
 }

 if($data->{'uselist'}->in_use($data->{'new_virtual'}))
 {
  return error("The target file '$new_virtual' already exists and it is edited by someone else.",$dir);
 }

 rename($physical,$new_physical) or return error("Could not move/rename '".encode_entities($virtual)."' to '$new_virtual'.",upper_path($virtual));
 return devedit_reload({command => 'show', file => $dir});
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

 return exec_rmdir($data,$config) if(-d $physical);
 return error_in_use($virtual)    if($data->{'uselist'}->in_use($virtual));

 unlink($physical) or return error("Could not delete file '".encode_entities($virtual)."'.",upper_path($virtual));
 return devedit_reload({command => 'show', file => upper_path($virtual)});
}

# exec_rmdir()
#
# Remove a directory and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_rmdir($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};

 return exec_remove($data,$config) if(not -d $physical);

 if($data->{'cgi'}->param('confirmed'))
 {
  rmtree($physical);
  return devedit_reload({command => 'show', file => upper_path($virtual)});
 }
 else
 {
  my $dir = encode_entities(upper_path($virtual));
  my $output;

  $output  = htmlhead("Remove directory $virtual");
  $output .= equal_url($config->{'httproot'},$virtual);

  $virtual = encode_entities($virtual);

  $output .= dir_link($virtual);

  $output .= <<"END";
<p>Do you really want to remove the directory '$virtual' and all of it's files and sub directories?</p>

<form action="$script" method="get">
<input type="hidden" name="command" value="rmdir">
<input type="hidden" name="file" value="$virtual">
<input type="hidden" name="confirmed" value="1">

<p><input type="submit" value="Yes"></p>
</form>

<form action="$script" method="get">
<input type="hidden" name="command" value="show">
<input type="hidden" name="file" value="$dir">

<p><input type="submit" value="No"></p>
</form>
END

  $output .= htmlfoot;

  return \$output;
 }
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

 return devedit_reload({command => 'show', file => upper_path($virtual)});
}

# it's true, baby ;-)

1;

#
### End ###