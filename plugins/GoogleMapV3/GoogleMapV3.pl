package MT::Plugin::GoogleMapV3;
use strict;
use MT;
use MT::Plugin;
use base qw( MT::Plugin );

our $VERSION = '1.11';
our $SCHEMA_VERSION = '0.974';

my $plugin = MT::Plugin::GoogleMapV3->new( {
    id => 'GoogleMapV3',
    key => 'googlemapv3',
    description => '<__trans phrase=\'Available GoogleMap(API version 3)\'>',
    name => 'GoogleMapV3',
    author_name => 'okayama',
    author_link => 'http://weeeblog.net/',
    version => $VERSION,
    schema_version => $SCHEMA_VERSION,
    l10n_class => 'GoogleMapV3::L10N',
    blog_config_template => 'googlemapv3_config_blog.tmpl',
    settings => new MT::PluginSettings( [
        [ 'use_googlemap', { Default => 1 } ],
        [ 'use_googlemap_page', { Default => 1 } ],
        [ 'default_lat', { Default => '35.658629995310946' } ],
        [ 'default_lon', { Default => '139.74546879529953' } ],
        [ 'default_level', { Default => 12 } ],
        [ 'default_address', { Default => '' } ],
    ] ),
} );

MT->add_plugin( $plugin );

sub init_registry {
    my $plugin = shift;
    $plugin->registry( {
        object_types => {
            'entry' => {
                'lat' => 'text',
                'lon' => 'text',
            },
            'category' => {
                'lat' => 'text',
                'lon' => 'text',
                'level' => 'text',
            },
        },
        callbacks => {
            'MT::App::CMS::template_source.header',
                => \&_cb_ts_header,
            'MT::App::CMS::template_param.edit_entry',
                => \&_cb_tp_edit_entry,
            'MT::App::CMS::template_param.edit_category',
                => \&_cb_tp_edit_category,
            'api_post_save.entry',
                => \&_api_post_save_entry,
        },
        tags => {
            block => {
                'IfBlogUseGoogleMap?' => \&_hdlr_if_blog_use_google_map,
            },
            function => {
                'GoogleMapURL' => \&_hdlr_googlemap_url,
                'BlogGoogleMapDefaultLat' => \&_hdlr_blog_googlemap_default_lat,
                'BlogGoogleMapDefaultLon' => \&_hdlr_blog_googlemap_default_lon,
                'BlogGoogleMapDefaultLevel' => \&_hdlr_blog_googlemap_default_level,
                'CategoryGoogleMapLat' => \&_hdlr_category_googlemap_lat,
                'CategoryGoogleMapLon' => \&_hdlr_category_googlemap_lon,
                'CategoryGoogleMapLevel' => \&_hdlr_category_googlemap_level,
                'EntryGoogleMapLat' => \&_hdlr_entry_googlemap_lat,
                'EntryGoogleMapLon' => \&_hdlr_entry_googlemap_lon,
            },
         }
   } );
}

sub _cb_ts_header {
    my ( $cb, $app, $tmpl ) = @_;
    return 1 unless $app->mode eq 'view';
    return 1 unless $app->param( '_type' );
    return 1 unless $app->param( '_type' ) =~ /(entry|page)/;
    if ( my $blog_id = $app->param( 'blog_id' ) ) {
        my $scope = 'blog:' . $blog_id;
        return 1 unless $plugin->get_config_value( 'use_googlemap' . ( $app->param( '_type' ) eq 'page' ? '_page' : '' ), $scope );
        my $search = quotemeta( '</head>' );
        my $header_script = &_header_script();
        $$tmpl =~ s/($search)/$header_script$1/;
    }
}

sub _header_script {
    return<<'MTML';
        <script type="text/javascript" src="http://www.google.com/jsapi"></script>
        <script type="text/javascript" src="http://maps.google.com/maps/api/js?sensor=false&language=ja" charset="UTF-8"></script>
        <script type="text/javascript">
        $().ready( function() {
            var mapdiv = document.getElementById( 'google-map' );
            var geocoder = new google.maps.Geocoder();
            var org_lat = '<mt:var name="default_lat">';
            var org_lng = '<mt:var name="default_lon">';
            var point = new google.maps.LatLng( org_lat, org_lng );
            var myOptions = {
                zoom: <$mt:var name="default_level_setting"$>,
                center: point,
                mapTypeId: google.maps.MapTypeId.ROADMAP,
                streetViewControl : true
            };
            
            var image = new google.maps.MarkerImage(
                '<mt:var name="static_uri">plugins/GoogleMapV3/images/center.gif',
                new google.maps.Size( 39, 39 ),
                new google.maps.Point( 0, 0 ),
                new google.maps.Point( 19, 19 )
            );
            
            var map = new google.maps.Map( mapdiv, myOptions );
            var marker = new google.maps.Marker( {
                icon: image,
                position: point,
                map: map,
                draggable: false
            } );
            var sad = '<mt:var name="default_address">';
            var geocoder = new google.maps.Geocoder();
            geocoder.geocode( { 'address': sad }, function ( results, status ) {
                if ( status == google.maps.GeocoderStatus.OK ) {
                    map.setCenter( results[ 0 ].geometry.location );
                    marker.setPosition( results[ 0 ].geometry.location );
                } else {
                    var alt_lat = '<mt:var name="default_lat">';
                    var alt_lng = '<mt:var name="default_lon">';
                    var alt_point = new google.maps.LatLng( alt_lat, alt_lng );
                    map.setCenter( alt_point );
                    marker.setPosition( alt_point );
                }
            } );
            google.maps.event.addListener( map, 'idle', mapMoveEvent );
            google.maps.event.addListener( map, 'drag', mapDragEvent );
            function mapMoveEvent() {
                var xy = map.getCenter();
                if ( document.getElementById( "lat" ) ) {
                    document.getElementById( "lat" ).value = xy.lat();
                }
                if ( document.getElementById( "lon" ) ) {
                    document.getElementById( "lon" ).value = xy.lng();
                }
            }
            function mapDragEvent() {
                marker.setPosition( map.getCenter() );
            }
        } );
        </script>
MTML
}

# _api_post_save_entry
# save Lat and Lon
sub _api_post_save_entry {
    my ( $cb, $app, $entry, $orig ) = @_;
    my $blog_id = $app->param( 'blog_id' ) || $entry->blog_id;
    if ( $blog_id ) {
        my $scope = 'blog:' . $blog_id;
        return 1 unless $plugin->get_config_value( 'use_googlemap', $blog_id );
        $entry->lat( $app->param( 'lat' ) );
        $entry->lon( $app->param( 'lon' ) );
        $entry->save or return $app->error( $app->translate(
                                                "Saving [_1] failed: [_2]", $entry->class_label,
                                                $entry->errstr
                                            )
                                          );
    }
}

sub _cb_tp_edit_entry {
    my ( $cb, $app, $param, $tmpl ) = @_;
    if ( my $blog_id = $app->param( 'blog_id' ) ) {
        my $scope = 'blog:' . $blog_id;
        return 1 unless $plugin->get_config_value( 'use_googlemap' . ( $app->param( '_type' ) eq 'page' ? '_page' : '' ), $scope );
        $$param{ default_lat } = $plugin->get_config_value( 'default_lat', $scope );
        $$param{ default_lon } = $plugin->get_config_value( 'default_lon', $scope );
        $$param{ default_level_setting } = $plugin->get_config_value( 'default_level', $scope );
        $$param{ default_address } = $plugin->get_config_value( 'default_address', $scope );
        if ( my $pointer_field = $tmpl->getElementById( 'tags' ) ) {
            my ( $nodeset );
            # set map
            $nodeset = $tmpl->createElement( 'app:setting', { id => 'googlemap-map',
                                                              label => $plugin->translate( 'Map.' ),
                                                              required => 0,
                                                              label_class => 'top-label',
                                                            },
                                           );
            $nodeset->innerHTML( &_entry_map_field() );
            $tmpl->insertBefore( $nodeset, $pointer_field );
            # set point field
            $nodeset = $tmpl->createElement( 'app:setting', { id => 'point',
                                                              label => $plugin->translate( 'Point.' ),
                                                              required => 0,
                                                              label_class => 'no-header',
                                                            },
                                           );
            $nodeset->innerHTML( &_entry_point_field() );
            $tmpl->insertBefore( $nodeset, $pointer_field );
        }
    }
}

sub _cb_tp_edit_category {
    my ( $cb, $app, $param, $tmpl ) = @_;
    if ( my $blog_id = $app->param( 'blog_id' ) ) {
        my $scope = 'blog:' . $blog_id;
        return 1 unless $plugin->get_config_value( 'use_googlemap', $scope );
        $$param{ default_lat } = $plugin->get_config_value( 'default_lat', $scope );
        $$param{ default_lon } = $plugin->get_config_value( 'default_lon', $scope );
        $$param{ default_level_setting } = $plugin->get_config_value( 'default_level', $scope );
        $$param{ default_address } = $plugin->get_config_value( 'default_address', $scope );
        if ( my $pointer_field = $tmpl->getElementById( 'description' ) ) {
            my ( $nodeset );
            $nodeset = $tmpl->createElement( 'app:setting', { id => 'googlemap-setting',
                                                              label => $plugin->translate( 'Google Map' ),
                                                              required => 0,
                                                            },
                                           );
            $nodeset->innerHTML( &_category_setting_field() );
            $tmpl->insertAfter( $nodeset, $pointer_field );
        }
    }
}

######################################## tags ########################################

sub _hdlr_googlemap_url {
    my ( $ctx, $args, $cond ) = @_;
    my $lang = MT->current_language;
    if ( $lang eq 'ja' ) {
        return 'http://maps.google.co.jp/';
    } else {
        return 'http://maps.google.com/';
    }
}

sub _hdlr_if_blog_use_google_map {
    my ( $ctx, $args, $cond ) = @_;
    my $blog = $ctx->stash( 'blog' ) || return 0;
    my $scope = 'blog:' . $blog->id;
    return $plugin->get_config_value( 'use_googlemap', $scope ) || '';
}

sub _hdlr_blog_googlemap_default_lat {
    my ( $ctx, $args, $cond ) = @_;
    my $blog = $ctx->stash( 'blog' ) || return '';
    my $scope = 'blog:' . $blog->id;
    return $plugin->get_config_value( 'default_lat', $scope ) || '';
}

sub _hdlr_blog_googlemap_default_lon {
    my ( $ctx, $args, $cond ) = @_;
    my $blog = $ctx->stash( 'blog' ) || return '';
    my $scope = 'blog:' . $blog->id;
    return $plugin->get_config_value( 'default_lon', $scope ) || '';
}

sub _hdlr_blog_googlemap_default_level {
    my ( $ctx, $args, $cond ) = @_;
    my $blog = $ctx->stash( 'blog' ) || return '';
    my $scope = 'blog:' . $blog->id;
    return $plugin->get_config_value( 'default_level', $scope ) || '';
}

sub _hdlr_category_googlemap_lat {
    my ( $ctx, $args, $cond ) = @_;
    my $category = ( $_[0]->stash( 'category' ) || $_[0]->stash( 'archive_category' ) )
                        or return $_[0]->error( MT->translate(
                            "You used an [_1] tag outside of the proper context.",
                            '<$MT' . $_[0]->stash( 'tag' ) . '$>' ) );
    return $category->lat || '';
}

sub _hdlr_category_googlemap_lon {
    my ( $ctx, $args, $cond ) = @_;
    my $category = ( $_[0]->stash( 'category' ) || $_[0]->stash( 'archive_category' ) )
                        or return $_[0]->error( MT->translate(
                            "You used an [_1] tag outside of the proper context.",
                            '<$MT' . $_[0]->stash( 'tag' ) . '$>' ) );
    return $category->lon || '';
}

sub _hdlr_category_googlemap_level {
    my ( $ctx, $args, $cond ) = @_;
    my $category = ( $_[0]->stash( 'category' ) || $_[0]->stash( 'archive_category' ) )
                        or return $_[0]->error( MT->translate(
                            "You used an [_1] tag outside of the proper context.",
                            '<$MT' . $_[0]->stash( 'tag' ) . '$>' ) );
    return $category->level || '';
}

sub _hdlr_entry_googlemap_lat {
    my ( $ctx, $args, $cond ) = @_;
    my $entry = $ctx->stash( 'entry' ) or return $ctx->_no_entry_error( '<$MT' . $_[0]->stash( 'tag' ) . '$>' );
    return $entry->lat || '';
}

sub _hdlr_entry_googlemap_lon {
    my ($ctx, $args, $cond) = @_;
    my $entry = $ctx->stash( 'entry' ) or return $ctx->_no_entry_error( '<$MT' . $_[0]->stash( 'tag' ) . '$>' );
    return $entry->lon || '';
}

sub _category_setting_field {
    return<<'MTML';
        <__trans_section component="GoogleMapV3">
            <label for="lat" style="font-weight:bold;display:block;margin-bottom:3px;color:#333;"><__trans phrase="Default Lat."></label>
            <div class="textarea-wrapper" style="margin-bottom:10px;">
                <input type="text" name="lat" id="lat" class="full-width text" maxlength="100" value="<mt:if name="lat"><mt:var name="lat"><mt:else><mt:var name="default_lat"></mt:if>" />
            </div>
            <label for="lon" style="font-weight:bold;display:block;margin-bottom:3px;color:#333;"><__trans phrase="Default Lon."></label>
            <div class="textarea-wrapper" style="margin-bottom:10px;">
                <input type="text" name="lon" id="lon" class="full-width text" maxlength="100" value="<mt:if name="lon"><mt:var name="lon"><mt:else><mt:var name="default_lon"></mt:if>" />
            </div>
            <label for="level" style="font-weight:bold;display:block;margin-bottom:3px;color:#333;"><__trans phrase="Level."></label>
            <mt:unless name="level">
                <mt:var name="default_level_setting" setvar="level">
            </mt:unless>
            <select name="level" id="level">
                <option value="1"<mt:if name="level" eq="1"> selected="selected"</mt:if>>1</option>
                <option value="2"<mt:if name="level" eq="2"> selected="selected"</mt:if>>2</option>
                <option value="3"<mt:if name="level" eq="3"> selected="selected"</mt:if>>3</option>
                <option value="4"<mt:if name="level" eq="4"> selected="selected"</mt:if>>4</option>
                <option value="5"<mt:if name="level" eq="5"> selected="selected"</mt:if>>5</option>
                <option value="6"<mt:if name="level" eq="6"> selected="selected"</mt:if>>6</option>
                <option value="7"<mt:if name="level" eq="7"> selected="selected"</mt:if>>7</option>
                <option value="8"<mt:if name="level" eq="8"> selected="selected"</mt:if>>8</option>
                <option value="9"<mt:if name="level" eq="9"> selected="selected"</mt:if>>9</option>
                <option value="10"<mt:if name="level" eq="10"> selected="selected"</mt:if>>10</option>
                <option value="11"<mt:if name="level" eq="11"> selected="selected"</mt:if>>11</option>
                <option value="12"<mt:if name="level" eq="12"> selected="selected"</mt:if>>12</option>
                <option value="13"<mt:if name="level" eq="13"> selected="selected"</mt:if>>13</option>
                <option value="14"<mt:if name="level" eq="14"> selected="selected"</mt:if>>14</option>
                <option value="15"<mt:if name="level" eq="15"> selected="selected"</mt:if>>15</option>
            </select>
        </__trans_section>        
MTML
}

sub _entry_map_field {
    return<<'MTML';
        <__trans_section component="GoogleMapV3">
            <div id="google-map" style="height: 350px;"></div>
        </__trans_section>
MTML
}

sub _entry_point_field {
    return<<'MTML';
        <__trans_section component="GoogleMapV3">
                <__trans phrase="Lat."><br />
                <input type="text" name="lat" id="lat" class="full-width" value="<mt:if name="lat"><mt:var name="lat"><mt:else><mt:var name="default_lat"></mt:if>" style="margin-bottom: 5px;" /><br />
                <__trans phrase="Lon."><br />
                <input type="text" name="lon" id="lon" class="full-width" value="<mt:if name="lon"><mt:var name="lon"><mt:else><mt:var name="default_lon"></mt:if>" />
        </__trans_section>
MTML
}

1;