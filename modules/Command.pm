package Command;

#
# Dev-Editor - Module Command
#
# Execute Dev-Editor's commands
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2010-10-26
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

use vars qw(@EXPORT);

use Fcntl;
use File::Access;
use File::Copy;
use File::Path;

use Digest::MD5 qw(md5_hex);
use POSIX qw(strftime);
use Tool;

use CGI qw(header
           escape);

use Output;
use Template;

my $script = encode_html($ENV{'SCRIPT_NAME'});
my $users  = eval('getpwuid(0)') && eval('getgrgid(0)');

my %dispatch = ('show'         => \&exec_show,
                'beginedit'    => \&exec_beginedit,
                'endedit'      => \&exec_endedit,
                'download'     => \&exec_download,
                'mkdir'        => \&exec_mkdir,
                'mkfile'       => \&exec_mkfile,
                'upload'       => \&exec_upload,
                'copy'         => \&exec_copy,
                'rename'       => \&exec_rename,
                'remove'       => \&exec_remove,
                'remove_multi' => \&exec_remove_multi,
                'chprop'       => \&exec_chprop,
                'about'        => \&exec_about
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

 foreach(keys(%dispatch))
 {
  if(lc($_) eq lc($command))
  {
   my $output = &{$dispatch{$_}}($data,$config);
   return $output;
  }
 }

 return error($config->{'errors'}->{'command_unknown'},'/',{COMMAND => encode_html($command)});
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
 my $upper_path     = multi_string(upper_path($virtual));

 my $tpl = new Template;

 if(-d $physical && not -l $physical)
 {
  # Create directory listing

  return error($config->{'errors'}->{'no_dir_access'},$upper_path->{'normal'}) unless(-r $physical && -x $physical);

  my $direntries = dir_read($physical);
  return error($config->{'errors'}->{'dir_read_failed'},$upper_path->{'normal'},{DIR => encode_html($virtual)}) unless($direntries);

  my $files = $direntries->{'files'};
  my $dirs  = $direntries->{'dirs'};

  my $dirlist = '';

  my $count = 0;

  my $filter1 = $data->{'cgi'}->param('filter') || '*';        # The real wildcard
  my $filter2 = ($filter1 && $filter1 ne '*') ? $filter1 : ''; # Wildcard for output

  # Create the link to the upper directory
  # (only if the current directory is not the root directory)

  unless($virtual eq '/')
  {
   $count++;

   my @stat  = stat($physical.'/..');

   my $udtpl = new Template;
   $udtpl->read_file($config->{'templates'}->{'dirlist_up'});

   $udtpl->fillin('UPPER_DIR',$upper_path->{'html'});
   $udtpl->fillin('UPPER_DIR_URL',$upper_path->{'url'});
   $udtpl->fillin('DATE',encode_html(strftime($config->{'timeformat'},($config->{'use_gmt'}) ? gmtime($stat[9]) : localtime($stat[9]))));

   $dirlist .= $udtpl->get_template;
  }

  # Directories

  foreach my $dir(@$dirs)
  {
   next if($config->{'hide_dot_files'} && substr($dir,0,1) eq '.');
   next unless(dos_wildcard_match($filter1,$dir));

   $count++;

   my $phys_path = $physical.'/'.$dir;
   my $virt_path = multi_string($virtual.$dir.'/');

   my @stat      = stat($phys_path);

   my $dtpl = new Template;
   $dtpl->read_file($config->{'templates'}->{'dirlist_dir'});

   $dtpl->fillin('DIR',$virt_path->{'html'});
   $dtpl->fillin('DIR_URL',$virt_path->{'url'});
   $dtpl->fillin('DIR_NAME',encode_html($dir));
   $dtpl->fillin('DATE',encode_html(strftime($config->{'timeformat'},($config->{'use_gmt'}) ? gmtime($stat[9]) : localtime($stat[9]))));
   $dtpl->fillin('URL',equal_url(encode_html($config->{'httproot'}),$virt_path->{'html'}));

   $dtpl->parse_if_block('forbidden',is_forbidden_file($config->{'forbidden'},$virt_path->{'normal'}));
   $dtpl->parse_if_block('readable',-r $phys_path && -x $phys_path);
   $dtpl->parse_if_block('users',$users && -o $phys_path);
   $dtpl->parse_if_block('even',($count % 2) == 0);

   $dirlist .= $dtpl->get_template;
  }

  # Files

  foreach my $file(@$files)
  {
   next if($config->{'hide_dot_files'} && substr($file,0,1) eq '.');
   next unless(dos_wildcard_match($filter1,$file));

   $count++;

   my $phys_path = $physical.'/'.$file;
   my $virt_path = multi_string($virtual.$file);

   my @stat      = lstat($phys_path);
   my $too_large = $config->{'max_file_size'} && $stat[7] > $config->{'max_file_size'};

   my $ftpl = new Template;
   $ftpl->read_file($config->{'templates'}->{'dirlist_file'});

   $ftpl->fillin('FILE',$virt_path->{'html'});
   $ftpl->fillin('FILE_URL',$virt_path->{'url'});
   $ftpl->fillin('FILE_NAME',encode_html($file));
   $ftpl->fillin('FILE_URL',$virt_path->{'url'});
   $ftpl->fillin('SIZE',$stat[7]);
   $ftpl->fillin('DATE',encode_html(strftime($config->{'timeformat'},($config->{'use_gmt'}) ? gmtime($stat[9]) : localtime($stat[9]))));
   $ftpl->fillin('URL',equal_url(encode_html($config->{'httproot'}),$virt_path->{'html'}));

   $ftpl->parse_if_block('link',-l $phys_path);
   $ftpl->parse_if_block('readable',-r $phys_path);
   $ftpl->parse_if_block('writeable',-w $phys_path);
   $ftpl->parse_if_block('binary',-B $phys_path);

   $ftpl->parse_if_block('forbidden',is_forbidden_file($config->{'forbidden'},$virt_path->{'normal'}));
   $ftpl->parse_if_block('viewable',(-r $phys_path && -T $phys_path && not $too_large) || -l $phys_path);
   $ftpl->parse_if_block('editable',(-r $phys_path && -w $phys_path && -T $phys_path && not $too_large) && not -l $phys_path);

   $ftpl->parse_if_block('too_large',$config->{'max_file_size'} && $stat[7] > $config->{'max_file_size'});

   $ftpl->parse_if_block('users',$users && -o $phys_path);

   $ftpl->parse_if_block('even',($count % 2) == 0);

   $dirlist .= $ftpl->get_template;
  }

  $tpl->read_file($config->{'templates'}->{'dirlist'});

  $tpl->fillin('DIRLIST',$dirlist);
  $tpl->fillin('DIR',encode_html($virtual));
  $tpl->fillin('DIR_URL',escape($virtual));
  $tpl->fillin('SCRIPT',$script);
  $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));

  $tpl->fillin('FILTER',encode_html($filter2));
  $tpl->fillin('FILTER_URL',escape($filter2));

  $tpl->parse_if_block('empty',$dirlist eq '');
  $tpl->parse_if_block('dir_writeable',-w $physical);
  $tpl->parse_if_block('filter',$filter2);
  $tpl->parse_if_block('gmt',$config->{'use_gmt'});
 }
 elsif(-l $physical)
 {
  # Show the target of a symbolic link

  my $link_target = readlink($physical);

  $tpl->read_file($config->{'templates'}->{'viewlink'});

  $tpl->fillin('FILE',encode_html($virtual));
  $tpl->fillin('DIR',$upper_path->{'html'});
  $tpl->fillin('DIR_URL',$upper_path->{'url'});
  $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
  $tpl->fillin('SCRIPT',$script);

  $tpl->fillin('LINK_TARGET',encode_html($link_target));
 }
 else
 {
  # View a file

  return error($config->{'errors'}->{'no_view'},$upper_path->{'normal'}) unless(-r $physical);

  # Check on binary files
  # We have to do it in this way or empty files will be recognized
  # as binary files

  return error($config->{'errors'}->{'binary_file'},$upper_path->{'normal'}) unless(-T $physical);

  # Is the file too large?

  return error($config->{'errors'}->{'file_too_large'},$upper_path->{'normal'},{SIZE => $config->{'max_file_size'}}) if($config->{'max_file_size'} && -s $physical > $config->{'max_file_size'});

  # View the file

  my $content =  file_read($physical);
  $$content   =~ s/\015\012|\012|\015/\n/g;

  $tpl->read_file($config->{'templates'}->{'viewfile'});

  $tpl->fillin('FILE',encode_html($virtual));
  $tpl->fillin('FILE_URL',escape($virtual));
  $tpl->fillin('DIR',$upper_path->{'html'});
  $tpl->fillin('DIR_URL',$upper_path->{'url'});
  $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
  $tpl->fillin('SCRIPT',$script);

  $tpl->parse_if_block('editable',-w $physical);

  $tpl->fillin('CONTENT',encode_html($$content));
 }

 my $output  = header(-type => 'text/html');
 $output    .= $tpl->get_template;

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
 my $dir            = upper_path($virtual);

 return error($config->{'errors'}->{'link_edit'},$dir) if(-l $physical);
 return error($config->{'errors'}->{'dir_edit'}, $dir) if(-d $physical);
 return error($config->{'errors'}->{'no_edit'},  $dir) unless(-r $physical && -w $physical);

 # Check on binary files

 return error($config->{'errors'}->{'binary_file'},$dir) unless(-T $physical);

 # Is the file too large?

 return error($config->{'errors'}->{'file_too_large'},$dir,{SIZE => $config->{'max_file_size'}}) if($config->{'max_file_size'} && -s $physical > $config->{'max_file_size'});

 # Show the editing form

 my $content =  file_read($physical);
 my $md5sum  =  md5_hex($$content);
 $$content   =~ s/\015\012|\012|\015/\n/g;

 my $tpl = new Template;
 $tpl->read_file($config->{'templates'}->{'editfile'});

 $tpl->fillin('FILE',encode_html($virtual));
 $tpl->fillin('FILE_URL',escape($virtual));
 $tpl->fillin('DIR',encode_html($dir));
 $tpl->fillin('DIR_URL',escape($dir));
 $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
 $tpl->fillin('SCRIPT',$script);
 $tpl->fillin('MD5SUM',$md5sum);
 $tpl->fillin('CONTENT',encode_html($$content));

 $tpl->parse_if_block('error',0);

 my $output = header(-type => 'text/html');
 $output   .= $tpl->get_template;

 return \$output;
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
 my $dir            = upper_path($virtual);
 my $cgi            = $data->{'cgi'};
 my $content        = $cgi->param('filecontent');
 my $md5sum         = $cgi->param('md5sum');
 my $output;

 if(defined $content && $md5sum)
 {
  # Normalize newlines

  $content =~ s/\015\012|\012|\015/\n/g;

  if($cgi->param('saveas') && $data->{'new_physical'} ne '' && $data->{'new_virtual'} ne '')
  {
   # Create the new filename

   $physical = $data->{'new_physical'};
   $virtual  = $data->{'new_virtual'};
  }

  return error($config->{'errors'}->{'link_edit'},$dir)      if(-l $physical);
  return error($config->{'errors'}->{'dir_edit'},$dir)       if(-d $physical);
  return error($config->{'errors'}->{'no_edit'},$dir)        if(-e $physical && !(-r $physical && -w $physical));
  return error($config->{'errors'}->{'text_to_binary'},$dir) if(-e $physical && not -T $physical);

  # For technical reasons, we can't use file_save() for
  # saving the file...

  local *FILE;

  sysopen(FILE,$physical,O_RDWR | O_CREAT) or return error($config->{'errors'}->{'edit_failed'},$dir,{FILE => encode_html($virtual)});
  file_lock(*FILE,LOCK_EX)                 or do { close(FILE); return error($config->{'errors'}->{'edit_failed'},$dir,{FILE => encode_html($virtual)}) };

  my $md5 = new Digest::MD5;
  $md5->addfile(*FILE);

  my $md5file = $md5->hexdigest;
  my $md5data = md5_hex($content);

  if($md5file ne $md5sum && $md5data ne $md5file && not $cgi->param('saveas'))
  {
   # The file changed meanwhile

   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'editfile'});

   $tpl->fillin('ERROR',$config->{'errors'}->{'edit_file_changed'});

   $tpl->fillin('FILE',encode_html($virtual));
   $tpl->fillin('FILE_URL',escape($virtual));
   $tpl->fillin('DIR',encode_html($dir));
   $tpl->fillin('DIR_URL',escape($dir));
   $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
   $tpl->fillin('SCRIPT',$script);
   $tpl->fillin('MD5SUM',$md5file);
   $tpl->fillin('CONTENT',encode_html($content));

   $tpl->parse_if_block('error',1);

   my $data = header(-type => 'text/html');
   $data   .= $tpl->get_template;

   $output  = \$data;
  }
  else
  {
   if($md5data ne $md5file)
   {
    seek(FILE,0,0);
    truncate(FILE,0);

    print FILE $content;
   }

   $output = ($cgi->param('continue'))
           ? devedit_reload({command => 'beginedit', file => $virtual})
           : devedit_reload({command => 'show', file => $dir});
  }

  close(FILE);

  return $output;
 }

 return devedit_reload({command => 'beginedit', file => $virtual});
}

# exec_download()
#
# Execute a HTTP download of a file
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_download($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $dir            = upper_path($virtual);

 return return error($config->{'errors'}->{'no_download'},$dir,{FILE => $virtual}) if((not -r $physical) || (-d $physical || -l $physical));

 my $filename = file_name($virtual);

 my $output = header(-type => 'application/octet-stream', -attachment => $filename);
 $output   .= ${ file_read($physical,1) };

 return \$output;
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
 $new_virtual       = encode_html($new_virtual);

 if($new_physical)
 {
  return error($config->{'errors'}->{'file_exists'},$dir,{FILE => $new_virtual}) if(-e $new_physical);

  file_create($new_physical) or return error($config->{'errors'}->{'mkfile_failed'},$dir,{FILE => $new_virtual});
  
  if($data->{'cgi'}->param('edit'))
  {
   return devedit_reload({command => 'beginedit', file => $new_virtual});
  }
  else
  {
   return devedit_reload({command => 'show', file => $dir});
  }
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'mkfile'});

  $tpl->fillin('DIR','/');
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
 }
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
 $new_virtual       = encode_html($new_virtual);

 if($new_physical)
 {
  return error($config->{'errors'}->{'file_exists'},$dir,{FILE => $new_virtual}) if(-e $new_physical);

  mkdir($new_physical,0777) or return error($config->{'errors'}->{'mkdir_failed'},$dir,{DIR => $new_virtual});
  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'mkdir'});

  $tpl->fillin('DIR','/');
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_upload()
#
# Process a file upload
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_upload($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $cgi            = $data->{'cgi'};

 return error($config->{'errors'}->{'no_directory'},upper_path($virtual),{FILE => encode_html($virtual)}) unless(-d $physical && not -l $physical);
 return error($config->{'errors'}->{'dir_no_create'},$virtual,{DIR => encode_html($virtual)})             unless(-w $physical);

 if(my $uploaded_file = $cgi->param('uploaded_file'))
 {
  if($cgi->param('remote_file'))
  {
   $uploaded_file = $cgi->param('remote_file');

   $uploaded_file =~ s!/!!g;
   $uploaded_file =~ s!\\!!g;
  }

  # Process file upload

  my $filename  = file_name($uploaded_file);
  my $file_phys = $physical.'/'.$filename;
  my $file_virt = encode_html($virtual.$filename);

  if(-e $file_phys)
  {
   return error($config->{'errors'}->{'link_replace'},$virtual)                        if(-l $file_phys);
   return error($config->{'errors'}->{'dir_replace'},$virtual)                         if(-d $file_phys);
   return error($config->{'errors'}->{'exist_no_write'},$virtual,{FILE => $file_virt}) unless(-w $file_phys);
   return error($config->{'errors'}->{'file_exists'},$virtual,{FILE => $file_virt})    unless($cgi->param('overwrite'));
  }

  my $ascii  = $cgi->param('ascii');
  my $handle = $cgi->upload('uploaded_file');

  return error($config->{'errors'}->{'invalid_upload'},$virtual) unless($handle);

  # Read transferred file and write it to disk

  read($handle, my $data, -s $handle);
  $data =~ s/\015\012|\012|\015/\n/g if($ascii); # Replace line separators if transferring in ASCII mode
  file_save($file_phys,\$data,not $ascii) or return error($config->{'errors'}->{'mkfile_failed'},$virtual,{FILE => $file_virt});

  return devedit_reload({command => 'show', file => $virtual});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'upload'});

  $tpl->fillin('DIR',encode_html($virtual));
  $tpl->fillin('DIR_URL',escape($virtual));
  $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
 }
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
 my $virtual        = $data->{'virtual'};
 my $dir            = upper_path($virtual);
 my $new_physical   = $data->{'new_physical'};

 return error($config->{'errors'}->{'link_copy'},$dir) if(-l $physical);
 return error($config->{'errors'}->{'no_copy'},$dir)   unless(-r $physical);

 if($new_physical)
 {
  my $new_virtual = multi_string($data->{'new_virtual'});
  my $new_dir     = upper_path($new_virtual->{'normal'});

  if(-d $physical)
  {
   return error($config->{'errors'}->{'no_copy'},$dir)                                      unless(-x $physical);
   return error($config->{'errors'}->{'file_exists'},$dir,{FILE => $new_virtual->{'html'}}) if(-e $new_physical);
   return error($config->{'errors'}->{'dir_copy_self'},$dir)                                if(index($new_virtual->{'normal'},$virtual) == 0);

   dir_copy($physical,$new_physical) or return error($config->{'errors'}->{'copy_failed'},$dir,{FILE => encode_html($virtual), NEW_FILE => $new_virtual->{'html'}});
   return devedit_reload({command => 'show', file => $new_dir});
  }
  else
  {
   if(-e $new_physical)
   {
    return error($config->{'errors'}->{'link_replace'},$new_dir)                                    if(-l $new_physical);
    return error($config->{'errors'}->{'dir_replace'},$new_dir)                                     if(-d $new_physical);
    return error($config->{'errors'}->{'exist_no_write'},$new_dir,{FILE => $new_virtual->{'html'}}) unless(-w $new_physical);

    if(not $data->{'cgi'}->param('confirmed'))
    {
     my $tpl = new Template;
     $tpl->read_file($config->{'templates'}->{'confirm_replace'});

     $tpl->fillin('FILE',encode_html($virtual));
     $tpl->fillin('NEW_FILE',$new_virtual->{'html'});
     $tpl->fillin('NEW_FILENAME',file_name($new_virtual->{'html'}));
     $tpl->fillin('NEW_DIR',encode_html($new_dir));
     $tpl->fillin('DIR',encode_html($dir));
     $tpl->fillin('DIR_URL',escape($dir));

     $tpl->fillin('COMMAND','copy');
     $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
     $tpl->fillin('SCRIPT',$script);

     my $output = header(-type => 'text/html');
     $output   .= $tpl->get_template;

     return \$output;
    }
   }

   copy($physical,$new_physical) or return error($config->{'errors'}->{'copy_failed'},$dir,{FILE => encode_html($virtual), NEW_FILE => $new_virtual->{'html'}});
   return devedit_reload({command => 'show', file => $new_dir});
  }
 }
 else
 {
  if(-d $physical)
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'copydir'});

   $tpl->fillin('FILE',encode_html($virtual));
   $tpl->fillin('DIR',encode_html($dir));
   $tpl->fillin('DIR_URL',escape($dir));
   $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'copyfile'});

   $tpl->fillin('FILE',encode_html($virtual));
   $tpl->fillin('DIR',encode_html($dir));
   $tpl->fillin('DIR_URL',escape($dir));
   $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
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
 my $dir            = upper_path($virtual);
 my $new_physical   = $data->{'new_physical'};

 return error($config->{'errors'}->{'rename_root'},'/') if($virtual eq '/');
 return error($config->{'errors'}->{'no_rename'},$dir)  unless(-w upper_path($physical));

 if($new_physical)
 {
  my $new_virtual = multi_string($data->{'new_virtual'});
  my $new_dir     = upper_path($new_virtual->{'normal'});

  if(-e $new_physical)
  {
   return error($config->{'errors'}->{'dir_replace'},$new_dir)                           if(-d $new_physical && not -l $new_physical);
   return error($config->{'errors'}->{'exist_no_write'},$new_dir,{FILE => $new_virtual}) unless(-w $new_physical);

   if(not $data->{'cgi'}->param('confirmed'))
   {
    my $tpl = new Template;
    $tpl->read_file($config->{'templates'}->{'confirm_replace'});

    $tpl->fillin('FILE',encode_html($virtual));
    $tpl->fillin('NEW_FILE',$new_virtual->{'html'});
    $tpl->fillin('NEW_FILENAME',file_name($new_virtual->{'html'}));
    $tpl->fillin('NEW_DIR',encode_html($new_dir));
    $tpl->fillin('DIR',encode_html($dir));

    $tpl->fillin('COMMAND','rename');
    $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
    $tpl->fillin('SCRIPT',$script);

    my $output = header(-type => 'text/html');
    $output   .= $tpl->get_template;

    return \$output;
   }
  }

  move($physical,$new_physical) or return error($config->{'errors'}->{'rename_failed'},$dir,{FILE => encode_html($virtual), NEW_FILE => $new_virtual->{'html'}});
  return devedit_reload({command => 'show', file => $new_dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'renamefile'});

  $tpl->fillin('FILE',encode_html($virtual));
  $tpl->fillin('DIR',encode_html($dir));
  $tpl->fillin('DIR_URL',escape($dir));
  $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_remove()
#
# Remove a file or a directory and return to directory view
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
 my $dir            = upper_path($virtual);

 return error($config->{'errors'}->{'remove_root'},'/') if($virtual eq '/');
 return error($config->{'errors'}->{'no_delete'},$dir)  unless(-w upper_path($physical));

 if(-d $physical && not -l $physical)
 {
  # Remove a directory

  if($data->{'cgi'}->param('confirmed'))
  {
   rmtree($physical);
   return devedit_reload({command => 'show', file => $dir});
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'confirm_rmdir'});

   $tpl->fillin('DIR',encode_html($virtual));
   $tpl->fillin('DIR_URL',escape($virtual));
   $tpl->fillin('UPPER_DIR',encode_html($dir));
   $tpl->fillin('UPPER_DIR_URL',escape($dir));
   $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
 else
 {
  # Remove a file

  if($data->{'cgi'}->param('confirmed'))
  {
   unlink($physical) or return error($config->{'errors'}->{'delete_failed'},$dir,{FILE => $virtual});
   return devedit_reload({command => 'show', file => $dir});
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'confirm_rmfile'});

   $tpl->fillin('FILE',encode_html($virtual));
   $tpl->fillin('FILE_URL',escape($virtual));
   $tpl->fillin('DIR',encode_html($dir));
   $tpl->fillin('DIR_URL',escape($dir));
   $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
}

# exec_remove_multi()
#
# Remove a file or a directory and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_remove_multi($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $cgi            = $data->{'cgi'};

 my @files = $cgi->param('files');#
 my @new_files;

 if(@files)
 {
  foreach my $file(@files)
  {
   # Filter out some "bad" files (e.g. files going up in the
   # directory hierarchy or files containing slashes (it's too
   # dangerous...)

   next if($file =~ m!^\.+$!);
   next if($file =~ m!/!);
   next if($file =~ m!\\!);

   push(@new_files,$file);
  }
 }

 if(@new_files)
 {
  if($cgi->param('confirmed'))
  {
   my @success;
   my @failed;

   foreach my $file(@new_files)
   {
    my $file_path = clean_path($physical.'/'.$file);

    if(-e $file_path)
    {
     if(-d $file_path && not -l $file_path)
     {
      # Remove a directory

      if(rmtree($file_path))
      {
       push(@success,clean_path($file));
      }
      else
      {
       push(@failed,clean_path($file));
      }
     }
     else
     {
      # Remove a file

      if(unlink($file_path))
      {
       push(@success,clean_path($file));
      }
      else
      {
       push(@failed,clean_path($file));
      }
     }
    }
    else
    {
     push(@failed,clean_path($file));
    }
   }

   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'rmmulti'});

   if(scalar(@success) > 0)
   {
    if(scalar(@success) == scalar(@new_files) && scalar(@failed) == 0)
    {
     return devedit_reload({command => 'show', file => $virtual});
    }
    else
    {
     $tpl->parse_if_block('success',1);

     foreach my $file_success(@success)
     {
      $tpl->add_loop_data('SUCCESS',{FILE => encode_html($file_success),
                                     FILE_PATH => encode_html(clean_path($virtual.'/'.$file_success))});
     }

     $tpl->parse_loop('SUCCESS');
    }
   }
   else
   {
    $tpl->parse_if_block('success',0);
   }

   if(scalar(@failed) > 0)
   {
    $tpl->parse_if_block('failed',1);

    foreach my $file_failed(@failed)
    {
     $tpl->add_loop_data('FAILED',{FILE => encode_html($file_failed),
                                   FILE_PATH => encode_html(clean_path($virtual.'/'.$file_failed))});
    }

    $tpl->parse_loop('FAILED');
   }
   else
   {
    $tpl->parse_if_block('failed',0);
   }


   $tpl->fillin('DIR',encode_html($virtual));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'confirm_rmmulti'});

   foreach my $file(@new_files)
   {
    $tpl->add_loop_data('FILES',{FILE => encode_html($file),
                                 FILE_PATH => encode_html(clean_path($virtual.'/'.$file))});
   }

   $tpl->parse_loop('FILES');

   $tpl->fillin('COUNT',scalar(@new_files));

   $tpl->fillin('DIR',encode_html($virtual));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
 else
 {
  return devedit_reload({command => 'show', file => $virtual});
 }
}

# exec_chprop()
#
# Change the mode and the group of a file or a directory
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_chprop($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $dir            = upper_path($virtual);

 return error($config->{'errors'}->{'no_users'},$dir,{FILE => encode_html($virtual)})  unless($users);
 return error($config->{'errors'}->{'chprop_root'},'/')                                if($virtual eq '/');
 return error($config->{'errors'}->{'not_owner'},$dir,{FILE => encode_html($virtual)}) unless(-o $physical);
 return error($config->{'errors'}->{'chprop_link'},$dir)                               if(-l $physical);

 my $cgi   = $data->{'cgi'};
 my $mode  = $cgi->param('mode');
 my $group = $cgi->param('group');

 if($mode || $group)
 {
  if($mode)
  {
   # Change the mode

   return error($config->{'errors'}->{'invalid_mode'},$dir) unless($mode =~ /^[0-7]{3,}$/);
   chmod(oct($mode),$physical);
  }

  if($group)
  {
   # Change the group using the `chgrp` system command

   return error($config->{'errors'}->{'invalid_group'},$dir,{GROUP => encode_html($group)}) unless($group =~ /^[a-z0-9_]+[a-z0-9_-]*$/i);
   system('chgrp',$group,$physical);
  }

  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  # Display the form

  my @stat = stat($physical);
  my $mode = $stat[2];
  my $gid  = $stat[5];

  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'chprop'});

  # Insert file properties into the template

  $tpl->fillin('MODE_OCTAL',substr(sprintf('%04o',$mode),-4));
  $tpl->fillin('MODE_STRING',mode_string($mode));
  $tpl->fillin('GID',$gid);

  if(my $group = getgrgid($gid))
  {
   $tpl->fillin('GROUP',encode_html($group));
   $tpl->parse_if_block('group_detected',1);
  }
  else
  {
   $tpl->parse_if_block('group_detected',0);
  }

  # Insert other information

  $tpl->fillin('FILE',encode_html($virtual));
  $tpl->fillin('FILE_URL',escape($virtual));
  $tpl->fillin('DIR',encode_html($dir));
  $tpl->fillin('DIR_URL',escape($dir));
  $tpl->fillin('URL',encode_html(equal_url($config->{'httproot'},$virtual)));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_about()
#
# Display some information about Dev-Editor
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_about($$)
{
 my ($data,$config) = @_;

 my $tpl = new Template;
 $tpl->read_file($config->{'templates'}->{'about'});

 $tpl->fillin('SCRIPT',$script);

 # Dev-Editor's version number

 $tpl->fillin('VERSION',$data->{'version'});

 # Some path information

 $tpl->fillin('SCRIPT_PHYS',encode_html($ENV{'SCRIPT_FILENAME'}));
 $tpl->fillin('CONFIG_PATH',encode_html($data->{'configfile'}));
 $tpl->fillin('FILE_ROOT',  encode_html($config->{'fileroot'}));
 $tpl->fillin('HTTP_ROOT',  encode_html($config->{'httproot'}));

 # Perl

 $tpl->fillin('PERL_PROG',encode_html($^X));
 $tpl->fillin('PERL_VER', sprintf('%vd',$^V));

 # Information about the server

 $tpl->fillin('HTTPD',encode_html($ENV{'SERVER_SOFTWARE'}));
 $tpl->fillin('OS',   encode_html($^O));
 $tpl->fillin('TIME', encode_html(strftime($config->{'timeformat'},($config->{'use_gmt'}) ? gmtime : localtime)));

 $tpl->parse_if_block('gmt',$config->{'use_gmt'});

 # Process information

 $tpl->fillin('PID',$$);

 # The following information is only available on systems supporting
 # users and groups

 if($users)
 {
  # Dev-Editor is running on a system which allows users and groups
  # So we display the user and the group of our process

  my $uid = POSIX::getuid;
  my $gid = POSIX::getgid;

  $tpl->parse_if_block('users',1);

  # IDs of user and group

  $tpl->fillin('UID',$uid);
  $tpl->fillin('GID',$gid);

  # Names of user and group

  if(my $user = getpwuid($uid))
  {
   $tpl->fillin('USER',encode_html($user));
   $tpl->parse_if_block('user_detected',1);
  }
  else
  {
   $tpl->parse_if_block('user_detected',0);
  }

  if(my $group = getgrgid($gid))
  {
   $tpl->fillin('GROUP',encode_html($group));
   $tpl->parse_if_block('group_detected',1);
  }
  else
  {
   $tpl->parse_if_block('group_detected',0);
  }

  # Process umask

  $tpl->fillin('UMASK',sprintf('%04o',umask));
 }
 else
 {
  $tpl->parse_if_block('users',0);
 }

 my $output = header(-type => 'text/html');
 $output   .= $tpl->get_template;

 return \$output;
}

# it's true, baby ;-)

1;

#
### End ###