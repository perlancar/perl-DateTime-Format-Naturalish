package DateTime::Format::Naturalish::IDD;
# ABSTRACT: Date/time naturalish patterns for Indonesian language

use 5.010;
use strict;
use warnings;
use base qw(DateTime::Format::Naturalish);

sub h_DOW_FULL {
    state $data = {
        (map { $_ => 1 } qw(senin)),
        (map { $_ => 2 } qw(selasa)),
        (map { $_ => 3 } qw(rabu)),
        (map { $_ => 4 } qw(kamis)),
        (map { $_ => 5 } qw(jumat jum'at jumaat juma'at jumah jum'ah jumaah)),
        (map { $_ => 6 } qw(sabtu saptu)),
        (map { $_ => 7 } qw(minggu ahad)),
    };
}

sub h_DOW_ABBREV {
    state $data = {
        (map { $_ => 1 } qw(sen snn sn)),
        (map { $_ => 2 } qw(sel sls sl)),
        (map { $_ => 3 } qw(rab ra rb)),
        (map { $_ => 4 } qw(kam ka kms km)),
        (map { $_ => 5 } qw(jum jmt ju jm)),
        (map { $_ => 6 } qw(sab sap sbt sa sb)),
        (map { $_ => 7 } qw(mgg min ming mg mi ahd)),
    };
}

sub h_MONTH {
    state $data = {
        (map { $_ =>  1 } qw(januari)),
        (map { $_ =>  2 } qw(februari pebruari)),
        (map { $_ =>  3 } qw(maret)),
        (map { $_ =>  4 } qw(april)),
        (map { $_ =>  5 } qw(mei)),
        (map { $_ =>  6 } qw(juni)),
        (map { $_ =>  7 } qw(juli)),
        (map { $_ =>  8 } qw(agustus)),
        (map { $_ =>  9 } qw(september)),
        (map { $_ => 10 } qw(oktober)),
        (map { $_ => 11 } qw(november nopember)),
        (map { $_ => 12 } qw(desember)),

        # abbreviations
        (map { $_ =>  1 } qw(jan)),
        (map { $_ =>  2 } qw(feb peb)),
        (map { $_ =>  3 } qw(mar mrt)),
        (map { $_ =>  4 } qw(apr)),
        (map { $_ =>  5 } qw(mei)),
        (map { $_ =>  6 } qw(jun)),
        (map { $_ =>  7 } qw(jul)),
        (map { $_ =>  8 } qw(agu agt)),
        (map { $_ =>  9 } qw(sept sep)),
        (map { $_ => 10 } qw(okt)),
        (map { $_ => 11 } qw(nov nop)),
        (map { $_ => 12 } qw(des)),
    };
}

sub p_THIS { "ini" }
sub p_NEXT { ["depan", "berikutnya"] }
sub p_LAST { ["kemarin", "sebelumnya"] }
sub p_THIS_WEEKDAY { "<WEEKDAY> <THIS>" }
sub p_WEEKEND { ["akhir pekan", "akhir minggu"] }
sub p_LAST_WEEKDAY { "<WEEKEND> <LAST>" }
sub p_THIS_WEEKDAY { "<WEEKEND> <THIS>" }
sub p_NEXT_WEEKDAY { "<WEEKEND> <NEXT>" }

1;
