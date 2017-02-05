class ZCL_GEOCODER_CES definition
  public
  final
  create public .

public section.

  interfaces IF_GEOCODING_TOOL .

  class-data XNL type ABAP_CHAR1 value %_NEWLINE ##NO_TEXT.
  data JSON_DESERIALIZER type STRING value 'ABAP' ##NO_TEXT.

  methods HTTP_SEND
    importing
      !POST_DATA type STRING optional
      !URL type STRING optional
      !METHOD type STRING default 'GET'
      !HTTP_RFC_DEST type RFCDEST optional
      !FORM_FIELDS type TIHTTPNVP optional
      !CONTENT_TYPE type STRING optional
    exporting
      !HTTP_STATUS_CODE type I
      !HTTP_STATUS_MESSAGE type STRING
      value(RESPONSE_TEXT) type STRING
    exceptions
      SEND_ERROR
      RECEIVE_ERROR
      ERROR_CREATE_BY_URL
      ERROR_CREATE_BY_DEST
      PLEASE_SET_DESTINATION .
  class-methods GET_ABAP_REGION_BY_NAME
    importing
      !REGION type STRING
      !COUNTRY type LAND1
    returning
      value(REG_CODE) type REGIO .
  class-methods GET_ABAP_REGION_BY_POSTALCODE
    importing
      !POSTALCODE type AD_PSTCD1
      !COUNTRY type LAND1 optional
    returning
      value(REGION) type REGIO .
protected section.

  methods GEOCODE_ONE_ADDRESS_GOOGLE
    importing
      !AES_ADDRESS type AES_ADDR
      !XINFO type GEOCDXINFO optional
      !ALT_STRING type STRING optional
    changing
      !RESULTS type GEOCD_RES_TABLE
      !CHOICE type GEOCD_CHOICE_TABLE
      !RELEVANT_FIELDS type GEOCD_ADDR_RELFIELDS_SORTEDTAB
      !MESSAGES type AES_MSG_TABLE
      !CONTAINERS type AESC_SORTEDTABLE
      !CORRECTED_ADDRESSES type AES_ADDR_SORTEDTABLE
    exceptions
      HTTP_SEND_ERROR
      JSON_PARSE_ERROR
      ZCX_JSON .
  methods GEOCODE_ONE_ADDRESS_HCPQM
    importing
      !AES_ADDRESS type AES_ADDR
      !XINFO type GEOCDXINFO optional
      !ALT_STRING type STRING optional
    changing
      !RESULTS type GEOCD_RES_TABLE
      !CHOICE type GEOCD_CHOICE_TABLE
      !RELEVANT_FIELDS type GEOCD_ADDR_RELFIELDS_SORTEDTAB
      !MESSAGES type AES_MSG_TABLE
      !CONTAINERS type AESC_SORTEDTABLE
      !CORRECTED_ADDRESSES type AES_ADDR_SORTEDTABLE
    exceptions
      HTTP_SEND_ERROR
      ZCX_JSON .
private section.

  data HTTP_RFC_DEST type RFC_DEST .
  data GEOSERVICE type STRING value 'GOOGLE' ##NO_TEXT.
  data APIKEY type STRING .

  methods GET_CUSTOMIZING
    importing
      !SRCID type GEOSRCID
    exporting
      !RFC_DEST type RFCDEST
      !GEOSERVICE type STRING
      !APIKEY type STRING .
  methods SET_SAP_PRECISION
    importing
      !ACCURACY type I
    returning
      value(SAP_PRECISION) type STRING .
  methods PARSE_GMAPS_JSON
    importing
      !JSON_TEXT type STRING
    exporting
      !GEOCODE_HEADER type GEOCODE_HEADER_TYPE
      !PLACEMARKS type PLACEMARK_TTAB
    exceptions
      JSON_PARSE_ERROR
      ZCX_JSON .
  methods DESERIALIZE_JSON
    importing
      !JSON_STRING type STRING
      !DATA_TYPE type STRING optional
    changing
      value(ABAP_DATA) type ANY
    raising
      ZCX_JSON .
ENDCLASS.



CLASS ZCL_GEOCODER_CES IMPLEMENTATION.


  method DESERIALIZE_JSON.

    type-pools: abap.

    data:
      rtab       type abap_trans_resbind_tab,
      rlin       type abap_trans_resbind,
      oexcp      type ref to cx_root,
      etext      type string,
      json_xtext type xstring,
      json_text  type string.

    data:
      datadesc type ref to cl_abap_typedescr,
      strudesc type ref to cl_abap_structdescr,
      l_comp   type line of abap_compdescr_tab,
      dataref  type ref to data.

    field-symbols: <comp> type any.

    break-point id z_cesar.

    case me->json_deserializer.

      when 'ABAP'.

        call method zcl_json_handler=>json2abap
          exporting
            json_string = json_string
          changing
            abap_data   = abap_data.


      when 'TRID'.

        " First, built table rtab for id transformation

        strudesc ?= cl_abap_structdescr=>describe_by_data( abap_data ).
        loop at strudesc->components into l_comp.
          rlin-name = l_comp-name.
          assign component l_comp-name of structure abap_data to <comp>.
          get reference of <comp> into dataref.
          rlin-value = dataref.
          append rlin to rtab.
          clear rlin.
          clear dataref.
        endloop.

        " Second, convert JSON variable names to upper case.

        json_xtext = cl_abap_codepage=>convert_to( json_string ).
        data(reader) = cl_sxml_string_reader=>create( json_xtext ).
        data(writer) = cast if_sxml_writer( cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ) ).
        do.
          data(node) = reader->read_next_node( ).
          if node is initial.
            exit.
          endif.
          if node->type = if_sxml_node=>co_nt_element_open.
            data(attributes)  = cast if_sxml_open_element( node )->get_attributes( ).
            loop at attributes assigning field-symbol(<attribute>).
              if <attribute>->qname-name = 'name'.
                <attribute>->set_value(
                  to_upper( <attribute>->get_value( ) ) ).
              endif.
            endloop.
          endif.
          writer->write_node( node ).
        enddo.

        break-point id z_cesar.

        json_xtext = cast cl_sxml_string_writer( writer )->get_output( ) .
        json_text = cl_abap_codepage=>convert_from( json_xtext ).

        try.

            " Then, do the transformation:

            call transformation id source xml json_text result (rtab).

          catch cx_root into oexcp.

            etext = oexcp->if_message~get_text( ).

            raise exception type zcx_json
              exporting
                message = etext.

        endtry.

      when others.
    endcase.

    break-point id z_cesar.


  endmethod.


method GEOCODE_ONE_ADDRESS_GOOGLE.

  data:
    lv_address     type adrc_struc,
    lv_result      type geocd_ress,
    lv_choice      type geocd_choi,
    lv_aesc        type aesc_tabs,
    lv_message     type aes_msg,
    aesc_container type aesc,
    ls_container   type line of aesc_sortedtable,
    corr_address   type line of aes_addr_sortedtable,
    wa_aesc        type aesc_struc.

  data:
    lv_address_query type string, " Parámetro address para google maps
    form_fields      type tihttpnvp,
    waff             type ihttpnvp,
    jsonresp         type string,
*  cxmlresp           type xstring,
    geocode_header   type geocode_header_type,
    placemarks       type placemark_ttab,
    wa_placemark     type line of placemark_ttab,
    lv_timezone_r3   type timezone,
    lv_timestamp     type timestamp,
    abap_country     type land1,
    str_country      type landx,
    iso_country      type intca,
    li               type i,
    idx              type i.


  if alt_string is not initial.
    lv_address_query = alt_string.

  else.

    if aes_address-address-street is not initial.
*      concatenate aes_address-address-street ' ' into lv_address_query.
      lv_address_query = aes_address-address-street.
    endif.

    if aes_address-address-house_num1 is not initial.
      concatenate lv_address_query aes_address-address-house_num1 into lv_address_query separated by space.
    endif.

    if aes_address-address-post_code1 is not initial.
      concatenate lv_address_query aes_address-address-post_code1 into lv_address_query separated by space.
    endif.

    if aes_address-address-city1 is not initial.
      concatenate lv_address_query aes_address-address-city1 into lv_address_query separated by space.
    endif.

    if aes_address-address-country is not initial.
      call function 'DR_GET_COUNTRY_NAME'
        EXPORTING
          country  = aes_address-address-country
          language = 'E'
        IMPORTING
          name     = str_country.
      concatenate lv_address_query str_country into lv_address_query separated by space.
    endif.

  endif.


* Conecta con google
  waff-name = 'key'.
  waff-value = me->apikey.
  append waff to form_fields. clear waff.

  waff-name = 'address'.
  waff-value = lv_address_query.
  append waff to form_fields. clear waff.

** Google option for components=country:<XX>
  waff-name = 'components'.
  concatenate 'country' aes_address-address-country into waff-value separated by ':'.
  append waff to form_fields. clear waff.


  call method me->http_send
    exporting
*     POST_DATA              =
*     URL                    =
      method                 = 'GET'
      http_rfc_dest          = me->http_rfc_dest
      form_fields            = form_fields
    importing
*     HTTP_STATUS_CODE       =
*     HTTP_STATUS_MESSAGE    =
      response_text          = jsonresp
    exceptions
      send_error             = 1
      receive_error          = 2
      error_create_by_url    = 3
      error_create_by_dest   = 4
      please_set_destination = 5
      others                 = 6.
  if sy-subrc <> 0.
    raise http_send_error.
  endif.
*
*  data conv type ref to CL_ABAP_CONV_IN_CE.
*    data xlen type i.
*  conv = CL_ABAP_CONV_IN_CE=>create( encoding = 'UTF-8' ). " ISO-8859-1
*  conv->convert( exporting input = cxmlresp  importing data = xmlresp len = xlen ).


* Parse google geocode JSON results

  call method me->parse_gmaps_json
    EXPORTING
      json_text        = jsonresp
    IMPORTING
      geocode_header   = geocode_header
      placemarks       = placemarks
    EXCEPTIONS
      json_parse_error = 1.

  if sy-subrc <> 0.
    raise json_parse_error.
  endif.

* Prepara result y choices, solo si google devuelve OK
  lv_result-id = aes_address-id.
  lv_result-info = geocode_header-status.


  if geocode_header-status eq 'OK'.

    describe table placemarks lines li.

* Dominio de valores para res:
*0  Geocodificación con éxito. Resultado unívoco.
*1  Geocodificación innecesaria (ninguna modificación relevante)
*2  Resultado no unívoco. La mejor selección (proceso de fondo)
*3  Resultado no unívoco. Existe selección de dirección.
*4  Resultado no unívoco. Ning.selección dirección (demasiados)
*5  Geocodificación no ha tenido éxito. Lon=Lat=Alt=invariable
*6  Herramienta no competente. Lon=Lat=Alt=invariable.
    if li eq 1.
      lv_result-res = 0.
      lv_result-info = 'Univoque Address'.
    elseif li gt 1.
      lv_result-res = 3.
      lv_result-info = 'Multiple Choice'.
    else.
      lv_result-res = 5.
      lv_result-info = 'Cannot Geocode Address'.
    endif.

    idx = 0.

    loop at placemarks into wa_placemark.

      add 1 to idx.

      lv_address = aes_address-address.
      ls_container-id = aes_address-id.
      lv_choice-id = aes_address-id.
      lv_choice-ranking = idx.
      lv_choice-percentage = '100'.

* Longitud y latitud y otros datos de geocodificación

      wa_aesc-service = 'GEOCODING'.
      wa_aesc-field   = 'SRCID'.
      wa_aesc-value   = xinfo-srcid.
      append wa_aesc to aesc_container.  clear wa_aesc.
      wa_aesc-service = 'GEOCODING'.
      wa_aesc-field   = 'LONGITUDE'.
      wa_aesc-value   = wa_placemark-longitude.
      append wa_aesc to aesc_container.  clear wa_aesc.
      wa_aesc-service = 'GEOCODING'.
      wa_aesc-field   = 'LATITUDE'.
      wa_aesc-value   = wa_placemark-latitude.
      append wa_aesc to aesc_container.  clear wa_aesc.
*      wa_aesc-service = 'GEOCODING'.
*      wa_aesc-field   = 'ALTITUDE'.
*      wa_aesc-value   = wa_placemark-altitude.
*      append wa_aesc to aesc_container.  clear wa_aesc.
      wa_aesc-service = 'GEOCODING'.
      wa_aesc-field   = 'PRECISID'.
      wa_aesc-value   = wa_placemark-accuracy.  " Use google accuracy for that????
      append wa_aesc to aesc_container. clear wa_aesc.
      wa_aesc-service = 'GEOCODING'.
      wa_aesc-field   = 'TZONE'.
*  take the r/3 timezone for country
      data country type land1.
      country = wa_placemark-country.
      call function 'TZON_LOCATION_TIMEZONE'
        EXPORTING
          if_country        = country
        IMPORTING
          ef_timezone       = lv_timezone_r3
        EXCEPTIONS
          no_timezone_found = 1
          others            = 2.
      if sy-subrc eq 0.
        wa_aesc-value   = lv_timezone_r3.
      endif.
      append wa_aesc to aesc_container.  clear wa_aesc.
* Timestamp geocoding
      get time stamp field lv_timestamp.
      wa_aesc-service = 'GEOCODING'.
      wa_aesc-field   = 'SRCTSTMP'.
      wa_aesc-value   = lv_timestamp.
      append wa_aesc to aesc_container.  clear wa_aesc.

      ls_container-container = aesc_container.

* add container to Choices Dialog

      lv_choice-container = aesc_container.

      lv_address-city1 = wa_placemark-locality.
      lv_address-city2 = wa_placemark-distrito.
      lv_address-post_code1 = wa_placemark-postalcodenumber.
      lv_address-street = wa_placemark-street.
      lv_address-house_num1 = wa_placemark-street_number.
      iso_country = wa_placemark-country.
      call function 'COUNTRY_CODE_ISO_TO_SAP_ABA'
        exporting
          iso_code  = iso_country
        importing
          sap_code  = abap_country
*         NOT_UNIQUE       =
        exceptions
          not_found = 1
          others    = 2.
      if sy-subrc eq 0.
        lv_address-country = abap_country.
      endif.

      lv_address-region = get_abap_region_by_name( REGION = wa_placemark-provincia_name COUNTRY = abap_country ).
      if lv_address-region is initial.
        lv_address-region = get_abap_region_by_postalcode( postalcode = lv_address-post_code1 country = abap_country ).
      endif.


      lv_choice-address = lv_address.
      lv_choice-addr_short = wa_placemark-fulladdress.


      append lv_choice to choice.

      " Solo si el resultado es unívoco devuelve containers y dirección corregida
      if lv_result-res = 0.
        modify table containers from ls_container.
        corr_address-id = aes_address-id.
        corr_address-address = lv_address.
        append corr_address to corrected_addresses.
      endif. "lv_result-res = 0

      break-point id z_cesar.

      " Y borras variables temporales
      clear corr_address.
      clear lv_choice.
      clear lv_address.
      clear ls_container.
      clear aesc_container.

    endloop.  " Placemarks



  else.       " Google Status other than OK
*5  Geocodificación no ha tenido éxito. Lon=Lat=Alt=invariable
*    lv_result-res = 5.
    lv_result-res = 6.
    lv_result-info = 'Failed Geocoding'.

  endif.      " Google Status OK

  append lv_result to results.


endmethod.


method GEOCODE_ONE_ADDRESS_HCPQM.

  data:
    lv_address     type adrc_struc,
    lv_result      type geocd_ress,
    lv_choice      type geocd_choi,
    lv_aesc        type aesc_tabs,
    lv_message     type aes_msg,
    aesc_container type aesc,
    ls_container   type line of aesc_sortedtable,
    corr_address   type line of aes_addr_sortedtable,
    wa_aesc        type aesc_struc.

  data:
    lv_address_query type string, " Parámetro address para google maps
    form_fields      type tihttpnvp,
    waff             type ihttpnvp,
    jsontext         type string,
    jsonquery        type string,
    jsonresp         type string,
*  cxmlresp           type xstring,
    geocode_header   type geocode_header_type,
    placemarks       type placemark_ttab,
    wa_placemark     type line of placemark_ttab,
    lv_timezone_r3   type timezone,
    lv_timestamp     type timestamp,
    abap_country     type land1,
    str_country      type landx,
    iso_country      type intca,
    li               type i,
    idx              type i,
    http_status_code type i,
    http_status_msg  type string.

* Prepare JSON query

  data: addressinput type hcp_query_addrinput.
  data: outputfields type stringtab.
  data: hcpresponse  type hcp_response.

  append 'addr_latitude' to outputfields.
  append 'addr_longitude' to outputfields.
  append 'geo_asmt_level' to outputfields.
  append 'geo_info_code' to outputfields.
  append 'geo_info_code_msg' to outputfields.
  append 'std_addr_prim_name1_4' to outputfields.
  append 'std_addr_prim_number_full' to outputfields.
  append 'std_addr_secaddr_no_floor_room' to outputfields.
  append 'std_addr_floor_number' to outputfields.
  append 'std_addr_room_number' to outputfields.
  append 'std_addr_building_name1_2' to outputfields.
  append 'addr_remainder_extra_pmb_full' to outputfields.
  append 'std_addr_point_of_ref1_2' to outputfields.
  append 'std_addr_locality3_4_full' to outputfields.
  append 'std_addr_locality_full' to outputfields.
  append 'std_addr_locality2_full' to outputfields.
  append 'std_addr_region_full' to outputfields.
  append 'std_addr_postcode_full' to outputfields.
  append 'std_addr_country_2char' to outputfields.
  append 'std_addr_po_box_number' to outputfields.
  append 'std_addr_po_box_locality_full' to outputfields.
  append 'std_addr_po_box_region_full' to outputfields.
  append 'std_addr_po_box_postcode_full' to outputfields.
  append 'std_addr_po_box_country_2char' to outputfields.
  append 'addr_info_code' to outputfields.
  append 'addr_info_code_msg' to outputfields.
  append 'addr_po_box_info_code' to outputfields.
  append 'addr_po_box_info_code_msg' to outputfields.

* Fill address input

  addressinput-street      = aes_address-address-street.
  addressinput-house_num   = aes_address-address-house_num1.
  addressinput-locality    = aes_address-address-city1.
  addressinput-postcode    = aes_address-address-post_code1.
  addressinput-country     = aes_address-address-country.

* Prepare post json query

  jsonquery = zcl_json_handler=>abap2json( name = 'addressInput' abap_data = addressinput ).
  jsontext = zcl_json_handler=>abap2json( name = 'outputFields' abap_data = outputfields ).
  concatenate '{' jsonquery ',' jsontext '}' into jsonquery.

  break-point id z_cesar.

  call method me->http_send
    exporting
      POST_DATA              = jsonquery
*     URL                    =
      method                 = 'POST'
      http_rfc_dest          = me->http_rfc_dest
      content_type           = 'application/json'
*     form_fields            = form_fields
    importing
      HTTP_STATUS_CODE       = http_status_code
      HTTP_STATUS_MESSAGE    = http_status_msg
      response_text          = jsonresp
    exceptions
      send_error             = 1
      receive_error          = 2
      error_create_by_url    = 3
      error_create_by_dest   = 4
      please_set_destination = 5
      others                 = 6.
  if sy-subrc <> 0.
    raise http_send_error.
  endif.

  break-point id z_cesar.

  deserialize_json( exporting json_string = jsonresp changing abap_data = hcpresponse ).

  break-point id z_cesar.

* HCP indicates success by 200 at HTTP status level
  if http_status_code eq 200.
    " HCP only returns unique address, no multiple lists
    lv_result-res = 0.
    lv_result-info = 'Univoque Address'.
    lv_address = aes_address-address.
    ls_container-id = aes_address-id.
    lv_choice-id = aes_address-id.
    lv_choice-ranking = 1.
    lv_choice-percentage = '100'.

* Set longitude, latitude and others
    wa_aesc-service = 'GEOCODING'.
    wa_aesc-field   = 'SRCID'.
    wa_aesc-value   = xinfo-srcid.
    append wa_aesc to aesc_container.  clear wa_aesc.
    wa_aesc-service = 'GEOCODING'.
    wa_aesc-field   = 'LONGITUDE'.
    wa_aesc-value   = hcpresponse-addr_longitude.
    append wa_aesc to aesc_container.  clear wa_aesc.
    wa_aesc-service = 'GEOCODING'.
    wa_aesc-field   = 'LATITUDE'.
    wa_aesc-value   = hcpresponse-addr_latitude.
    append wa_aesc to aesc_container.  clear wa_aesc.
    wa_aesc-service = 'GEOCODING'.
    wa_aesc-field   = 'PRECISID'.
    wa_aesc-value   = hcpresponse-geo_asmt_level.  " Use google accuracy for that????
    append wa_aesc to aesc_container. clear wa_aesc.
    wa_aesc-service = 'GEOCODING'.
    wa_aesc-field   = 'TZONE'.
*  take the r/3 timezone for country
    data country type land1.
    country = wa_placemark-country.
    call function 'TZON_LOCATION_TIMEZONE'
      EXPORTING
        if_country        = country
      IMPORTING
        ef_timezone       = lv_timezone_r3
      EXCEPTIONS
        no_timezone_found = 1
        others            = 2.
    if sy-subrc eq 0.
      wa_aesc-value   = lv_timezone_r3.
    endif.
    append wa_aesc to aesc_container.  clear wa_aesc.
* Timestamp geocoding
    get time stamp field lv_timestamp.
    wa_aesc-service = 'GEOCODING'.
    wa_aesc-field   = 'SRCTSTMP'.
    wa_aesc-value   = lv_timestamp.
    append wa_aesc to aesc_container.  clear wa_aesc.

    ls_container-container = aesc_container.
    lv_choice-container = aesc_container.

    lv_address-city1         = hcpresponse-std_addr_locality_full.
*      lv_address-city2        = wa_placemark-distrito.
    lv_address-post_code1    = hcpresponse-std_addr_postcode_full.
    lv_address-street        = hcpresponse-std_addr_prim_name1_4.
    lv_address-house_num1    = hcpresponse-std_addr_prim_number_full.
    iso_country              = hcpresponse-std_addr_country_2char.

    call function 'COUNTRY_CODE_ISO_TO_SAP_ABA'
      exporting
        iso_code  = iso_country
      importing
        sap_code  = abap_country
*       NOT_UNIQUE       =
      exceptions
        not_found = 1
        others    = 2.
    if sy-subrc eq 0.
      lv_address-country = abap_country.
    endif.

    lv_address-region = get_abap_region_by_name( REGION = hcpresponse-std_addr_region_full COUNTRY = abap_country ).
    if lv_address-region is initial.
      lv_address-region = get_abap_region_by_postalcode( postalcode = lv_address-post_code1 country = abap_country ).
    endif.

    lv_choice-address = lv_address.
    lv_choice-addr_short = lv_address-street.

    append lv_choice to choice.

    " Solo si el resultado es unívoco devuelve containers y dirección corregida
    if lv_result-res = 0.
      modify table containers from ls_container.
      corr_address-id = aes_address-id.
      corr_address-address = lv_address.
      append corr_address to corrected_addresses.
    endif. "lv_result-res = 0

    append lv_result to results.


  endif.





endmethod.


  method GET_ABAP_REGION_BY_NAME.

    types:
      begin of reglist_type,
        bezei type string,
        bland type regio,
      end of reglist_type.

    data reglist type hashed table of reglist_type with unique key bezei.
    field-symbols <reg> type reglist_type.

    select * from T005U into corresponding fields of table reglist  where land1 eq country and spras eq SY-LANGU.

    if sy-subrc eq 0.

      read table reglist with table key bezei = region assigning <reg>.

      if sy-subrc eq 0.

        reg_code = <reg>-bland.

      endif.

    endif.


  endmethod.


  method GET_ABAP_REGION_BY_POSTALCODE.

    " Get region from postal code
    " It only works like this in France and Spain: (AFAIK)
    " The first two digits indicate the 'département' (France) or "provicia" (Spain).

    data(pcode) = postalcode.
    condense pcode.

    if strlen( pcode ) eq 5.

       region = substring( val = pcode off = 0 len = 2 ).

    endif.


  endmethod.


method GET_CUSTOMIZING.

  data:
  lv_geocd2cls type geocd2cls.

* read http rfc dest from customizing
  select single * from geocd2cls into lv_geocd2cls where srcid = srcid.

  if sy-subrc ne 0.
*     if nothing found set a "sensible" default
    rfc_dest = 'HTTP_GMAPS_GEOCODE_SIM'.
    geoservice = 'GOOGLE'.
    exit.
  else.

    rfc_dest = lv_geocd2cls-rfc_dest.

    if lv_geocd2cls-funcname is not initial.
      geoservice = lv_geocd2cls-funcname.
      translate geoservice to upper case.
    endif.

    apikey = lv_geocd2cls-infostring.

  endif.

endmethod.


method HTTP_SEND.

  data client type ref to if_http_client.
  data destination(255) type c.
  data errcode type sysubrc.
  data errmesg type string.
  data oref type ref to cx_root.

  if http_rfc_dest is not initial.

    destination = http_rfc_dest.

    call method cl_http_client=>create_by_destination
      exporting
        destination              = destination
      importing
        client                   = client
      exceptions
        argument_not_found       = 1
        destination_not_found    = 2
        destination_no_authority = 3
        plugin_not_active        = 4
        internal_error           = 5
        others                   = 6.
    if sy-subrc <> 0.
      raise error_create_by_dest.
    endif.

  elseif url is not initial.

    call method cl_http_client=>create_by_url
      exporting
        url                = url
*    PROXY_HOST         =
*    PROXY_SERVICE      =
*    SSL_ID             =
*    SAP_USERNAME       =
*    SAP_CLIENT         =
      importing
        client             = client
      exceptions
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        others             = 4
            .
    if sy-subrc <> 0.
      raise error_create_by_url.
    endif.

  else.

    raise please_set_destination.

  endif.

  client->request->set_method( method ).
  if method eq 'POST' and post_data is not initial.
    client->request->set_cdata( post_data ).
    if content_type is not initial.
      client->request->set_content_type( content_type ).
    endif.
  endif.

  if form_fields is not initial.
    client->request->set_form_fields( form_fields ).
  endif.

  try.
      client->send( ).
    catch cx_root into oref.
  endtry.
  client->get_last_error( importing code = errcode message = errmesg ).

  if errcode ne 0.
    raise send_error.
  endif.

  try.
      client->receive( ).
    catch cx_root into oref.
  endtry.
  client->get_last_error( importing code = errcode message = errmesg ).

  if errcode ne 0.
    raise receive_error.
  endif.


  client->response->get_status( importing code = http_status_code reason = http_status_message ).
  response_text = client->response->get_cdata( ).



endmethod.


method IF_GEOCODING_TOOL~GEOCODE.

  break-point id z_cesar.

  data method_name type string.

  data:
  lv_aes_address type aes_addr.


* Get HTTP rfc destination from customizing:
  get_customizing(
        exporting
                    srcid = xinfo-srcid
        importing
                    rfc_dest   = me->http_rfc_dest
                    geoservice = me->geoservice
                    apikey     = me->apikey ).

* Set method for geoservice:
  concatenate 'GEOCODE_ONE_ADDRESS_' me->geoservice into method_name.

* Process addresses:
  loop at addresses into lv_aes_address.

*   geocode addresses one by one
    call method (method_name)
      exporting
        aes_address         = lv_aes_address
        xinfo               = xinfo
      changing
        results             = results
        choice              = choice
        relevant_fields     = relevant_fields
        messages            = messages
        containers          = containers
        corrected_addresses = corrected_addresses.

  endloop.

endmethod.


method PARSE_GMAPS_JSON.

  data google_results type zgoogle_results_type.
  data grestabfortrid type table of zgoogle_results_type.
  data res_wa         type ZGOOGLE_RESULTS_ITEM.
  data adc_wa         type ZGOOGLE_ADDCOMP_ITEM.

  data res_type type string.  " result types
  data adc_type type string.  " address components types

  data wa_placemark type line of placemark_ttab.

* Process Google returned JSON:

  CALL METHOD ME->DESERIALIZE_JSON
    EXPORTING
      JSON_STRING = json_text
      DATA_TYPE   = 'ZGOOGLE_RESULTS_TYPE'
    CHANGING
      ABAP_DATA   = google_results.

  geocode_header-status = google_results-status.
  geocode_header-error_message = google_results-error_message.

  if google_results-status ne 'OK'.
    exit.
  endif.

  loop at google_results-results into res_wa.

    wa_placemark-id           = res_wa-place_id.
    wa_placemark-fulladdress  = res_wa-formatted_address.
    wa_placemark-accuracy     = res_wa-geometry-location_type.
    wa_placemark-longitude    = res_wa-geometry-location-lng.
    wa_placemark-latitude     = res_wa-geometry-location-lat.

    find first occurrence of 'street_address' in table res_wa-types.

    if sy-subrc eq 0. " process it, it looks like a street address

      loop at res_wa-address_components into adc_wa.

        data adcomp type string.
        read table adc_wa-types index 1 into adcomp.
        if adcomp eq 'political'.
          read table adc_wa-types index 2 into adcomp.
        endif.

        case adcomp.
          when 'street_number'.
            wa_placemark-street_number = adc_wa-long_name.
          when 'route'.
            wa_placemark-street = adc_wa-long_name.
          when 'locality'.
            wa_placemark-locality = adc_wa-long_name.
          when 'administrative_area_level_2'.
            wa_placemark-provincia = adc_wa-short_name.
            wa_placemark-provincia_name = adc_wa-long_name.
          when 'administrative_area_level_1'.
            wa_placemark-comunidad = adc_wa-long_name.
          when 'country'.
            wa_placemark-country = adc_wa-short_name.
            wa_placemark-country_name = adc_wa-long_name.
          when 'postal_code'.
            wa_placemark-postalcodenumber = adc_wa-long_name.
        endcase.

      endloop.

    endif.

    append wa_placemark to placemarks.
    clear wa_placemark.

  endloop.


endmethod.


method SET_SAP_PRECISION.
* This method sets SAP APO defined precission codes
* for geocoding, as defined in a SAP APO system.
* The mapping is a bit "subjective" as there is not one-to-one correspondence.
* It is not always possible to map service accuracy to APO precision.

* SAP precission codes (in APO system):
*0000  No existen datos
*0100  Mundo
*0200  Continente
*0300  País
*0400  Región
*0500  Límite de municipio
*0600  Código postal
*0700  Población
*0800  Distrito
*0900  Punto medio de calle
*1000  Punto medio rango números casas (sección de calle)
*1100  Número casa (interpolado)
*1200  Número casa (exacto)
*1300  Número casa c/suplemento (p. ej., Neurottstr.7b)


  case accuracy.
    when 0.
      sap_precision = '0000'.
    when 1.
      sap_precision = '0300'.
    when 2.
      sap_precision = '0400'.
    when 3.
      sap_precision = '0500'.
    when 4.
      sap_precision = '0700'.
    when 5.
      sap_precision = '0600'.
    when 6.
      sap_precision = '0900'.
    when 7.
      sap_precision = '1000'.
    when 8 or 9.
      sap_precision = '1300'.
    when others.
      " which others?
  endcase.




endmethod.
ENDCLASS.
