#! /usr/bin/env perl

use MooseX::Declare;
use Soric3::Kernel;
use AnyEvent;

my $client = class extends Soric3::Module with Soric3::Role::SendQueue {
    method requirements($class:) {
        'Irc'
    }

    method BUILD( $ ) {
        $self->log(debug => 'Entering client code.');
        $self->module('Irc')->new_connection(
            tag => 'freenode', nickname => 'soric-test',
            host => 'irc.freenode.net');
        $self->queue_message(freenode => [PRIVMSG => sorear => 'Hello!']);
        $self->log(debug => 'Message queued.');
    }
};

my $kernel = Soric3::Kernel->new(client_class => $client);

AnyEvent->condvar->recv;
