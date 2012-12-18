
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Business::CPI's PayPal driver",
  "AUTHOR" => "Andr\303\251 Walker <andre\@andrewalker.net>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Business-CPI-Gateway-PayPal",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Business::CPI::Gateway::PayPal",
  "PREREQ_PM" => {
    "Business::CPI" => "0.2",
    "Business::PayPal::IPN" => 0,
    "Business::PayPal::NVP" => 0,
    "DateTime" => 0,
    "DateTime::Format::Strptime" => 0,
    "Moo" => 0
  },
  "VERSION" => "0.6",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



