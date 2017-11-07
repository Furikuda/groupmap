var all_maps;
var temp_marker;

var map = L.map('map', {
    minZoom: 2,
    maxZoom: 7,
    crs: L.CRS.Simple
}).setView([-20, 100], 3);
var marker_layer = new L.LayerGroup();

function make_fluff_popup_text(fluff) {
    var html = '<b>'+fluff.name+'</b>';
    if (fluff.info) {
        html += "<p>";
        html += fluff.info.replace(/(http[^ ]+)/, function(match, url) {return "<a href='" + url + "'>" + url + "</a>"});
        html += "</p>";
    }
    return html
}

function add_fluff(fluff, map_folder) {
     $.ajax({
        url: "/add_fluff",
        type: "POST",
        dataType: "json",
        data: fluff,
        success: function(data, textStatus) {
            temp_marker.closePopup();
            load_fluff(map_folder);
        },
        error: function(data) {
            console.log(data.responseText);
//            toastr.options.timeOut = 1500;
//            toastr.options.positionClass= "toast-top-center";
//            toastr.error(data.responseText);
        }
    });
}

function show_fluff_marker(evt){
    var lat = evt.latlng.lat;
    var lng = evt.latlng.lng;

    if (typeof temp_marker !== 'undefined') {
        temp_marker.unbindPopup();
        temp_marker.remove();
    }

    temp_marker = L.marker([lat, lng]).addTo(marker_layer);

    var popupContent = "Who is that Fluff?"+
        "<form id='add-fluff-form'>" +
        "<input type='text' name='name' id='add-fluff-name-field' placeholder='Fluff name'>" +
        "<input type='text' name='info' id='add-fluff-info-field' placeholder='extra info of link'>" +
        "<input type='hidden' name='lng' id='add-fluff-lng-field' value='"+lng+"'>" +
        "<input type='hidden' name='lat' id='add-fluff-lat-field' value='"+lat+"'>" +
        "<input type='submit' value='Save'>" +
        "</form>";

    temp_marker.bindPopup(popupContent,{
                    keepInView: true,
                    }).openPopup();

    $('#add-fluff-form').on('submit', function(e) {
        e.preventDefault();
        var fluff = {};
        fluff.name = $('#add-fluff-name-field').val();
        fluff.info = $('#add-fluff-info-field').val();
        fluff.lat = $('#add-fluff-lat-field').val();
        fluff.lng = $('#add-fluff-lng-field').val();
        add_fluff(fluff, evt.target.map_folder);
    });
}

function load_fluff(f) {
    $.ajax({
        url: "/list_fluff?map="+f,
        dataType: "json",
        success: function(data, textStatus) {
            marker_layer.eachLayer(function (layer) {
                    marker_layer.removeLayer(layer);
            });
            for (var i in data['fluff']) {
                fluff = data['fluff'][i];
                var popup_content = make_fluff_popup_text(fluff)
                var marker = L.marker([fluff.lat, fluff.lng])
                marker.bindPopup(popup_content);
                marker.addTo(marker_layer);
            }
            marker_layer.addTo(map);
        },
        error: function(data) {
            console.log(data.responseText);
//            toastr.options.timeOut = 1500;
//            toastr.options.positionClass= "toast-top-center";
//            toastr.error(data.responseText);
        }
    });
}

function show_map(map_folder) {
    map.eachLayer(function (layer) {
            map.removeLayer(layer);
    });

    var info_text = '' ;

    var tiles = L.tileLayer('/group_pics/'+map_folder+'/{z}/{y}/{x}.jpg', {
        minzoom: 2,
        maxzoom: 7,
        noWrap: true,
        attribution: info_text,
    })
    tiles.addTo(map);
    map.map_folder = map_folder;
    map.on('click', show_fluff_marker);
    load_fluff(map_folder);
}

function switch_markers() {
    var pane = map.getPane('markerPane');
    if (document.getElementById('show_markers_switch').checked) {
        pane.style.zIndex = 650;
    } else {
        pane.style.zIndex = 0;
    }
}

function load_maps() {
    $.ajax({
        url: "/list_maps",
        dataType: "json",
        success: function(data, textStatus) {
            all_maps = data['maps'];
            show_map(all_maps[0]['folder']);
        },
        error: function(data) {
            console.log(data.responseText);
//            toastr.options.timeOut = 1500;
//            toastr.options.positionClass= "toast-top-center";
//            toastr.error(data.responseText);
        }
    });
}
