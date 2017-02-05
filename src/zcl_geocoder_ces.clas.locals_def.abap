*"* use this source file for any type of declarations (class
*"* definitions, interfaces or type declarations) you need for
*"* components in the private section

** Auxiliary types

* Placemark generic transport:

types: begin of placemark_type,
         id               type string,
         fulladdress      type string,
         country          type string,
         country_name     type string,
         locality         type string,
         distrito         type string,
         provincia        type string,
         provincia_name   type string,
         comunidad        type string,
         street           type string,      " street
         street_number    type string,
         postalcodenumber type string,
         longitude        type string,
         latitude         type string,
         accuracy         type string,
         accuracy_desc    type string,
       end of placemark_type.

types: placemark_ttab type table of placemark_type.

types: begin of geocode_header_type,
         status        type string,
         error_message type string,
       end of geocode_header_type.

* Data structures for the HCP Data Quality microservices for location data
* http://help.sap.com/saphelpiis_dqmmicro1/dqm_micro_loc_1_dev_en/frameset.htm

types: begin of hcp_query_addrinput,
         street          type string,
         house_num       type string,
         house_num2      type string,
         floor           type string,
         roomnumber      type string,
         building        type string,
         street_suppl    type string,
         street_suppl2   type string,
         street_suppl3   type string,
         location        type string,
         locality        type string,
         locality2       type string,
         locality3       type string,
         region          type string,
         postcode        type string,
         country         type string,
         po_box          type string,
         po_box_locality type string,
         po_box_region   type string,
         po_box_postcode type string,
         po_box_country  type string,
       end of hcp_query_addrinput.


types: begin of hcp_response,
         addr_po_box_info_code          type string,
         addr_info_code_msg             type string,
         std_addr_po_box_postcode_full  type string,
         std_addr_prim_name1_4          type string,
         addr_remainder_extra_pmb_full  type string,
         std_addr_point_of_ref1_2       type string,
         addr_info_code                 type string,
         std_addr_po_box_region_full    type string,
         std_addr_building_name1_2      type string,
         std_addr_room_number           type string,
         std_addr_po_box_number         type string,
         std_addr_secaddr_no_floor_room type string,
         std_addr_po_box_country_2char  type string,
         std_addr_postcode_full         type string,
         std_addr_country_2char         type string,
         std_addr_po_box_locality_full  type string,
         std_addr_region_full           type string,
         std_addr_locality3_4_full      type string,
         addr_po_box_info_code_msg      type string,
         std_addr_locality2_full        type string,
         std_addr_prim_number_full      type string,
         std_addr_floor_number          type string,
         std_addr_locality_full         type string,
         geo_asmt_level                 type string,
         geo_info_code                  type string,
         geo_info_code_msg              type string,
         addr_latitude                  type string,
         addr_longitude                 type string,
       end of hcp_response.
