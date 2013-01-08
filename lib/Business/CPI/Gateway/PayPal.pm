package Business::CPI::Gateway::PayPal;
# ABSTRACT: Business::CPI's PayPal driver

use Moo;
use DateTime;
use DateTime::Format::Strptime;
use Business::PayPal::IPN;
use Business::PayPal::NVP;
use Carp 'croak';

our $VERSION = '0.9'; # VERSION

extends 'Business::CPI::Gateway::Base';

has sandbox => (
    is => 'rw',
    default => sub { 0 },
);

has '+checkout_url' => (
    default => sub {
        my $sandbox = shift->sandbox ? 'sandbox.' : '';
        return "https://www.${sandbox}paypal.com/cgi-bin/webscr";
    },
    lazy => 1,
);

has '+currency' => (
    default => sub { 'USD' },
);

# TODO: make it lazy, and croak if needed
has api_username => (
    is => 'ro',
    required => 0,
);

has api_password => (
    is => 'ro',
    required => 0,
);

has signature    => (
    is => 'ro',
    required => 0,
);

has nvp => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;

        return Business::PayPal::NVP->new(
            test => {
                user => $self->api_username,
                pwd  => $self->api_password,
                sig  => $self->signature,
            },
            live => {
                user => $self->api_username,
                pwd  => $self->api_password,
                sig  => $self->signature,
            },
            branch => $self->sandbox ? 'test' : 'live'
        );
    }
);

has date_format => (
    is => 'ro',
    lazy => 1,
    default => sub {
        DateTime::Format::Strptime->new(
            pattern   => '%Y-%m-%dT%H:%M:%SZ',
            time_zone => 'UTC',
        );
    },
);

sub notify {
    my ( $self, $req ) = @_;

    if ($self->sandbox) {
        $Business::PayPal::IPN::GTW = 'https://www.sandbox.paypal.com/cgi-bin/webscr';
    }
    else {
        $Business::PayPal::IPN::GTW = 'https://www.paypal.com/cgi-bin/webscr';
    }

    my $ipn = Business::PayPal::IPN->new( query => $req )
        or die Business::PayPal::IPN->error;

    my %vars = $ipn->vars;

    my $result = {
        payment_id             => $vars{invoice},
        gateway_transaction_id => $vars{txn_id},
        exchange_rate          => $vars{exchange_rate},
        status                 => undef,
        net_amount             => ($vars{settle_amount} || $vars{mc_gross}) - ($vars{mc_fee} || 0),
        amount                 => $vars{mc_gross},
        fee                    => $vars{mc_fee},
        date                   => $vars{payment_date},
        payer => {
            name => $vars{first_name} . ' ' . $vars{last_name},
        }
    };

    if ($ipn->completed) {
        $result->{status} = 'completed';
    }
    elsif (my $reason = $ipn->pending) {
        $result->{status} = 'processing';
    }
    elsif ($ipn->failed || $ipn->denied) {
        $result->{status} = 'failed';
    }
    else {
        return {}; # unknown status
    }

    return $result;
}

sub query_transactions {
    my ($self, $info) = @_;

    my $final_date   = $info->{final_date}   || DateTime->now(time_zone => 'UTC');
    my $initial_date = $info->{initial_date} || $final_date->clone->subtract(days => 30);

    my %search = $self->nvp->send(
        METHOD    => 'TransactionSearch',
        STARTDATE => $initial_date->strftime('%Y-%m-%dT%H:%M:%SZ'),
        ENDDATE   => $final_date->strftime('%Y-%m-%dT%H:%M:%SZ'),
    );

    if ($search{ACK} ne 'Success') {
        require Data::Dumper;
        croak "Error in the query: " . Data::Dumper::Dumper(\%search);
    }

    while (my ($k, $v) = each %search) {
        if ($k =~ /^L_TYPE(.*)$/) {
            my $deleted_key = "L_TRANSACTIONID$1";
            if (lc($v) ne 'payment') {
                delete $search{$deleted_key};
            }
        }
    }

    my @transaction_ids = map { $search{$_} } grep { /^L_TRANSACTIONID/ } keys %search;

    my @transactions    = map { $self->get_transaction_details($_) } @transaction_ids;

    return {
        current_page         => 1,
        results_in_this_page => scalar @transaction_ids,
        total_pages          => 1,
        transactions         => \@transactions,
    };
}

sub get_transaction_details {
    my ( $self, $id ) = @_;

    my %details = $self->nvp->send(
        METHOD        => 'GetTransactionDetails',
        TRANSACTIONID => $id,
    );

    if ($details{ACK} ne 'Success') {
        require Data::Dumper;
        croak "Error in the details fetching: " . Data::Dumper::Dumper(\%details);
    }

    return {
        payment_id    => $details{INVNUM},
        status        => lc $details{PAYMENTSTATUS},
        amount        => $details{AMT},
        net_amount    => $details{SETTLEAMT},
        tax           => $details{TAXAMT},
        exchange_rate => $details{EXCHANGERATE},
        date          => $self->date_format->parse_datetime($details{ORDERTIME}),
        buyer_email   => $details{EMAIL},
    };
}

sub get_hidden_inputs {
    my ($self, $info) = @_;

    my $buyer = $info->{buyer};
    my $cart  = $info->{cart};

    my @hidden_inputs = (
        # -- make paypal accept multiple items (cart)
        cmd           => '_ext-enter',
        redirect_cmd  => '_cart',
        upload        => 1,
        # --

        business      => $self->receiver_email,
        currency_code => $self->currency,
        charset       => $self->form_encoding,
        invoice       => $info->{payment_id},
        email         => $buyer->email,

        no_shipping   => $buyer->address_line1 ? 0 : 1,
    );

    my %buyer_extra = (
        address_line1    => 'address1',
        address_line2    => 'address2',
        address_city     => 'city',
        address_state    => 'state',
        address_country  => 'country',
        address_zip_code => 'zip',
    );

    for (keys %buyer_extra) {
        if (my $value = $buyer->$_) {
            # XXX: find a way to remove this check
            if ($_ eq 'country') {
                $value = uc $value;
            }
            push @hidden_inputs, ( $buyer_extra{$_} => $value );
        }
    }

    my %cart_extra = (
        discount => 'discount_amount_cart',
        handling => 'handling_cart',
        tax      => 'tax_cart',
    );

    for (keys %cart_extra) {
        if (my $value = $cart->$_) {
            push @hidden_inputs, ( $cart_extra{$_} => $value );
        }
    }

    my $i = 1;
    my $add_weight_unit = 0;

    foreach my $item (@{ $info->{items} }) {
        push @hidden_inputs,
          (
            "item_number_$i" => $item->id,
            "item_name_$i"   => $item->description,
            "amount_$i"      => $item->price,
            "quantity_$i"    => $item->quantity,
          );

        if (my $weight = $item->weight) {
            push @hidden_inputs, ( "weight_$i" => $weight );
            $add_weight_unit = 1;
        }

        if (my $ship = $item->shipping) {
            push @hidden_inputs, ( "shipping_$i" => $ship );
        }

        if (my $ship = $item->shipping_additional) {
            push @hidden_inputs, ( "shipping2_$i" => $ship );
        }
        $i++;
    }

    if ($add_weight_unit) {
        push @hidden_inputs, ( "weight_unit" => 'kgs' );
    }

    return @hidden_inputs;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Business::CPI::Gateway::PayPal - Business::CPI's PayPal driver

=head1 VERSION

version 0.9

=head1 ATTRIBUTES

=head2 sandbox

Boolean attribute to set whether it's running on sandbox or not. If it is, it
will post the form to the sandbox url in PayPal.

=head2 api_username

=head2 api_password

=head2 signature

=head2 nvp

Business::PayPal::NVP object, built using the api_username, api_password and
signature attributes.

=head2 date_format

DateTime::Format::Strptime object, to format dates in a way PayPal understands.

=head1 METHODS

=head2 notify

Translate IPN information from PayPal to a standard hash, the same way other
Business::CPI gateways do.

=head2 query_transactions

Searches transactions made by this account.

=head2 get_transaction_details

Get more data about a given transaction.

=head2 get_hidden_inputs

Get all the inputs to make a checkout form.

=head1 SPONSORED BY

Aware - L< http://www.aware.com.br >

=head1 AUTHOR

André Walker <andre@andrewalker.net>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by André Walker.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
