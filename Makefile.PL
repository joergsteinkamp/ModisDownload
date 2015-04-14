use 5.020001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'WebService::MODIS',
    VERSION_FROM      => 'lib/WebService/MODIS.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM         => {
      'Carp' => 1.3301,
      'LWP::Online' => 1.08,
      'LWP::UserAgent' => 6.06,
      'File::Path' => 2.09,
      'File::Basename' => 2.85,
      'Date::Simple' => 3.03,
      'List::Util' => 1.38
}, # e.g., Module::Name => 1.1
    ABSTRACT_FROM     => 'lib/WebService/MODIS.pm', # retrieve abstract from module
    AUTHOR            => 'Jörg Steinkamp <joergsteinkamp@yahoo.de>',
    #LICENSE           => 'perl',
    #Value must be from legacy list of licenses here
    #http://search.cpan.org/perldoc?Module%3A%3ABuild%3A%3AAPI
);
