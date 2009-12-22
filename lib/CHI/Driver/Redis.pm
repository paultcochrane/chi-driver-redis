package CHI::Driver::Redis;
use Moose;

use Redis;
use Try::Tiny;
use URI::Escape qw(uri_escape uri_unescape);

extends 'CHI::Driver';

has 'redis' => (
    is => 'rw',
    isa => 'Redis',
    lazy_build => 1
);

has '_params' => (
    is => 'rw'
);

sub BUILD {
    my ($self, $params) = @_;

    $self->_params($params);
    # $self->redis(
    #     Redis->new(
    #         server => $params->{server} || '127.0.0.1:6379',
    #         debug => $params->{debug} || 0
    #     )
    # );
}

sub _build_redis {
    my ($self) = @_;

    my $params = $self->_params;
    $self->redis(
        Redis->new(
            server => $params->{server} || '127.0.0.1:6379',
            debug => $params->{debug} || 0
        )
    );
}

sub fetch {
    my ($self, $key) = @_;

    $self->_verify_redis_connection;

    my $eskey = uri_escape($key);
    return $self->redis->get($self->namespace."||$eskey");
}

sub XXfetch_multi_hashref {
    my ($self, $keys) = @_;

    return unless scalar(@{ $keys });

    my %kv;
    foreach my $k (@{ $keys }) {
        my $esk = uri_escape($k);
        $kv{$self->namespace."||$esk"} = undef;
    }

    my @vals = $self->redis->mget(keys %kv);

    my $count = 0;
    my %resp;
    foreach my $k (@{ $keys }) {
        $resp{$k} = $vals[$count];
        $count++;
    }

    return \%resp;
}

sub get_keys {
    my ($self) = @_;

    my @keys = $self->redis->smembers($self->namespace);

    my @unesckeys = ();

    foreach my $k (@keys) {
        # Getting an empty key here for some reason...
        next unless defined $k;
        push(@unesckeys, uri_unescape($k));
    }
    return @unesckeys;
}

sub get_namespaces {
    my ($self) = @_;

    return $self->redis->smembers('chinamespaces');
}

sub remove {
    my ($self, $key) = @_;

    return unless defined($key);

    $self->_verify_redis_connection;

    my $ns = $self->namespace;

    my $skey = uri_escape($key);

    $self->redis->srem($ns, $skey);
    $self->redis->del("$ns||$skey");
}

sub store {
    my ($self, $key, $data, $expires_at, $options) = @_;

    $self->_verify_redis_connection;

    my $ns = $self->namespace;

    my $skey = uri_escape($key);
    my $realkey = "$ns||$skey";

    $self->redis->sadd('chinamespaces', $ns);
    unless($self->redis->sismember($ns, $skey)) {
        $self->redis->sadd($ns, $skey) ;
    }
    $self->redis->set($realkey => $data);

    if(defined($expires_at)) {
        my $secs = $expires_at - time;
        $self->redis->expire($realkey, $secs);
    }
}

sub _verify_redis_connection {
    my ($self) = @_;

    try {
        $self->redis->ping;
    } catch {
        warn "Error pinging redis, attempting to reconnect.\n";
        my $params = $self->_params;
        $self->redis(
            Redis->new(
                server => $params->{server} || '127.0.0.1:6379',
                debug => $params->{debug} || 0
            )
        );
    };
}

__PACKAGE__->meta->make_immutable;

no Moose;

__END__

=head1 NAME

CHI::Driver::Redis - Redis driver for CHI

=head1 SYNOPSIS

    use CHI;

    my $foo = CHI->new(
        driver => 'Redis',
        namespace => 'foo',
        server => '127.0.0.1:6379',
        debug => 0
    );

=head1 DESCRIPTION

A CHI driver that uses C<Redis> to store the data.

=head1 CONSTRUCTOR OPTIONS

C<server> and C<debug> are passed to C<Redis>.

=head1 ATTRIBUTES

=head2 redis

Contains the underlying C<Redis> object.

=head1 AUTHOR

Cory G Watson, C<< <gphat at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-chi-driver-redis at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CHI-Driver-Redis>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Cold Hard Code, LLC.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
