use Config;
$self->{LIBS} = ['-lssleay32 -llibeay32'] if $Config{cc} =~ /cl/;    # msvc with ActivePerl
$self->{LIBS} = ['-lssl32 -leay32']       if $Config{gccversion};    # gcc
