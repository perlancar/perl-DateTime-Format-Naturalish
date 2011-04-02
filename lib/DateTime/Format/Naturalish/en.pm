package DateTime::Format::Naturalish::en;
# ABSTRACT: Patterns for English language

use 5.010;
use strict;
use warnings;
use locale;

use base qw(DateTime::Format::Naturalish);
use vars qw($pat);

sub pdat_now { qr/^now$/ }

sub pdat_x_ago {
    my ($self) = @_;
    qr/^(?:(?<num> $pat->{num}) $pat->{wsep}? (?<period> period))+
       $pat->{wsep} ago$/x;
}

sub pdur_dummy { qr/^dummy$/ }

sub pset_dummy { qr/^dummy$/ }

1;
__END__

sub h_WEEKDAY {
    state $data = {
        (map { $_ => 1 } qw(monday)),
        (map { $_ => 2 } qw(tuesday)),
        (map { $_ => 3 } qw(wednesday)),
        (map { $_ => 4 } qw(thursday)),
        (map { $_ => 5 } qw(friday)),
        (map { $_ => 6 } qw(saturday)),
        (map { $_ => 7 } qw(sunday)),

        # abbreviations
        (map { $_ => 1 } qw(mon)),
        (map { $_ => 2 } qw(tue)),
        (map { $_ => 3 } qw(wed)),
        (map { $_ => 4 } qw(thu)),
        (map { $_ => 5 } qw(fri)),
        (map { $_ => 6 } qw(sat)),
        (map { $_ => 7 } qw(sun)),
    };
}

sub h_MONTH {
    state $data = {
        (map { $_ =>  1 } qw(january)),
        (map { $_ =>  2 } qw(february)),
        (map { $_ =>  3 } qw(march)),
        (map { $_ =>  4 } qw(april)),
        (map { $_ =>  5 } qw(may)),
        (map { $_ =>  6 } qw(june)),
        (map { $_ =>  7 } qw(july)),
        (map { $_ =>  8 } qw(august)),
        (map { $_ =>  9 } qw(september)),
        (map { $_ => 10 } qw(october)),
        (map { $_ => 11 } qw(november)),
        (map { $_ => 12 } qw(december)),

        # abbreviations
        (map { $_ =>  1 } qw(jan)),
        (map { $_ =>  2 } qw(feb)),
        (map { $_ =>  3 } qw(mar)),
        (map { $_ =>  4 } qw(apr)),
        (map { $_ =>  6 } qw(jun)),
        (map { $_ =>  7 } qw(jul)),
        (map { $_ =>  8 } qw(aug)),
        (map { $_ =>  9 } qw(sep)),
        (map { $_ => 10 } qw(oct)),
        (map { $_ => 11 } qw(nov)),
        (map { $_ => 12 } qw(dec)),
    };
}

sub t_THIS { "this" }

1;
