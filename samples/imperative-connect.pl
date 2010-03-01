#! /usr/bin/env perl

use MooseX::Declare;
use Soric3::Kernel;
use AnyEvent;

my $quit_cv = AnyEvent->condvar;

my $client = class extends Soric3::Module
        with (Soric3::Role::SendQueue, Soric3::Role::ConnectionObserver) {
    method requirements($class:) {
        'Irc'
    }

    method connection_status_changed(Str $tag) {
        if ($self->module('Irc')->connection_status('freenode')
                eq 'disconnected') {
            $quit_cv->send;
        }
    }

    method BUILD( $ ) {
        $self->log(debug => 'Entering client code.');
        $self->module('Irc')->new_connection(
            tag => 'freenode', nickname => 'soric-test',
            host => 'irc.freenode.net');
        $self->queue_message(freenode => [PRIVMSG => sorear => 'Hello!']);
        $self->log(debug => 'Message queued.');
        $self->queue_message(freenode => ['QUIT']);
    }
};

my $kernel = Soric3::Kernel->new(client_class => $client);

$quit_cv->recv;
