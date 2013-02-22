package NTPPool::Control::Scores;
use strict;
use base qw(NTPPool::Control);
use Combust::Constant qw(OK DECLINED);
use NP::Model;
use List::Util qw(min);
use JSON qw(encode_json);

sub render {
    my $self = shift;

    my $public = $self->site->name eq 'ntppool' ? 1 : 0;
    $self->cache_control('s-maxage=1200,max-age=600') if $public;

    unless ($public or $self->user) {
        $self->redirect($self->www_url($self->request->uri, $self->request->query_parameters));
    }

    if (!$public) {
        $self->tpl_param('manage_site', 1);
    }

    return $self->redirect('/scores/') if ($self->request->uri =~ m!^/s/?$!);

    if ($self->request->uri =~ m!^/s/([^/]+)!) {
        my $server = NP::Model->server->find_server($1) or return 404;
        $self->cache_control('max-age=14400, s-maxage=7200');
        return $self->redirect('/scores/' . $server->ip, 301);
    }

    if (my ($id, $mode) = ($self->request->uri =~ m!^/scores/graph/(\d+)-(score|offset).png!)) {
        my $server = NP::Model->server->find_server($id) or return 404;
        $self->cache_control('max-age=14400, s-maxage=7200');
        return $self->redirect($server->graph_uri($mode), 301);
    }

    if (my $ip = ($self->req_param('ip') || $self->req_param('server_ip'))) {
        my $server = NP::Model->server->find_server($ip) or return 404;
        return $self->redirect('/scores/' . $server->ip) if $server;
    }

    if (my ($p, $mode) = $self->request->uri =~ m!^/scores/([^/]+)(?:/(\w+))?!) {
        $mode ||= '';
        if ($p) {
            my ($server) = NP::Model->server->find_server($p);
            return 404 unless $server;
            return $self->redirect('/scores/' . $server->ip, 301) unless $p eq $server->ip;

            if ($mode eq 'monitors') {
                $self->cache_control('s-maxage=480,max-age=240') if $public;
                return OK, encode_json({monitors => $self->_monitors($server)}),
                  'application/json';
            }

            if ($mode eq 'log' or $self->req_param('log') or $mode eq 'json') {
                my $limit = $self->req_param('limit') || 0;
                $limit = 50 unless $limit and $limit !~ m/\D/;
                $limit = 4000 if $limit > 4000;
                my $since = $self->req_param('since') || 0;
                $since = 0 if $since =~ m/\D/;

                my $options = {
                    count      => $limit,
                    since      => $since,
                    monitor_id => $self->req_param('monitor'),
                };

                if ($since) {
                    $self->cache_control('s-maxage=300');
                }

                if ($mode eq 'json') {

                    #local ($Rose::DB::Object::Debug, $Rose::DB::Object::Manager::Debug) = (1, 1);
                    # This logic should probably just be in the server
                    # model, similar to log_scores_csv.

                    $self->request->header_out('Access-Control-Allow-Origin' => '*');

                    my $history = $server->history($options);
                    $history = [
                        map {
                            my $h      = $_;
                            my %h      = ();
                            my @fields = qw(offset step score monitor_id);
                            @h{@fields} = map { $h->$_; } @fields;
                            $h{ts} = $h->ts->epoch;
                            \%h;
                        } reverse @$history
                    ];
                    return OK,
                      encode_json(
                        {   history  => $history,
                            monitors => $self->_monitors($server),
                            server   => {ip => $server->ip}
                        }
                      ),
                      'application/json';
                }
                else {
                    return OK, $server->log_scores_csv($options), 'text/plain';
                }
            }
            elsif ($mode eq 'rrd') {
                return 404;
            }
            elsif ($mode eq 'graph') {
                my ($type) = ($self->request->uri =~ m{/(offset|score)\.png$});
                return $self->redirect($server->graph_uri($type), 301);
            }
            elsif ($mode eq '') {
                $self->tpl_param('graph_explanation' => 1) if $self->req_param('graph_explanation');
                $self->tpl_param('server' => $server);
            }
            else {
                return $self->redirect('/scores/' . $server->ip);
            }
        }
    }

    if ($self->req_param('graph_only')) {
        return OK, $self->evaluate_template('tpl/server_static_graph.html');
    }

    return OK, $self->evaluate_template('tpl/server.html');
}

sub _monitors {
    my ($self, $server) = @_;
    my $monitors = $server->server_scores;
    $monitors = [
        map {
            my %m = (
                id    => $_->monitor->id,
                score => $_->score,
                name  => $_->monitor->name,
            );
            \%m;
        } @$monitors
    ];
    return $monitors;
}

sub bc_user_class    { NP::Model->user }
sub bc_info_required {'username,email'}


1;
