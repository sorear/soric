#! /usr/bin/env perl

use MooseX::Declare;
use Soric3::Kernel;
use AnyEvent;

my $kernel = Soric3::Kernel->new(config => {}, client =>
    class extends Soric3::Module with Soric3::Role::SendQueue {
        method requires($class:) {
            'Soric3::Module::Irc'
        }

        method BUILD() {
            $self->module('Irc')->new_connection(
                tag => 'freenode', user => 'soric-test',
                host => 'irc.freenode.net');
            $self->queue_send(freenode => [PRIVMSG => sorear => 'Hello!']);
        }
    });

AnyEvent->cond_var->recv;
