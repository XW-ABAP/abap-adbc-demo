*&---------------------------------------------------------------------*
*& Include ZFIR057A_FRM
*&---------------------------------------------------------------------*

FORM frm_getdata_push.

  " --- 1. Data Definition Area ---
  DATA: lr_data         TYPE REF TO data.
  DATA: lv_submit_prog TYPE program,
        lv_submit_vari TYPE variant.

  " RTTS Description Objects
  DATA: lo_table_descr  TYPE REF TO cl_abap_tabledescr,
        lo_struct_descr TYPE REF TO cl_abap_structdescr,
        lt_components   TYPE cl_abap_structdescr=>component_table,
        ls_component    LIKE LINE OF lt_components.

  FIELD-SYMBOLS: <lt_alv_data> TYPE STANDARD TABLE,
                 <ls_row>      TYPE any,
                 <lv_value>    TYPE any.

  " --- 2. Get Configuration Table Data ---
  IF p_back = 'X'.
    SELECT * FROM zfir057at1
       INTO CORRESPONDING FIELDS OF TABLE gt_zfir057at1
       WHERE zblock_push = ''.
  ELSE.

  ENDIF.

  SELECT * FROM zfir057at2
    INTO TABLE @DATA(lt_zfir057at2).

  IF sy-subrc = 0.
    SORT lt_zfir057at2 BY progname variant.
  ENDIF.

  " Predefined Mapping Internal Table
  DATA: lt_mapping LIKE lt_zfir057at2.

  " --- 3. Loop Processing for Each ALV Program ---
  LOOP AT gt_zfir057at1 INTO DATA(ls_zfir057at1).

    " Reset Key Pointers and Variables
    CLEAR: lv_submit_prog, lv_submit_vari, lt_mapping.
    IF <lt_alv_data> IS ASSIGNED.
      UNASSIGN <lt_alv_data>.
    ENDIF.

    lv_submit_prog = to_upper( condense( ls_zfir057at1-progname ) ).
    lv_submit_vari = to_upper( condense( ls_zfir057at1-variant ) ).

    IF lv_submit_prog IS INITIAL. CONTINUE. ENDIF.

    " --- 4. Set Runtime Parameters and Execute ---
    cl_salv_bs_runtime_info=>clear( ).
    cl_salv_bs_runtime_info=>set(
      EXPORTING
        display  = abap_false
        metadata = abap_false
        data     = abap_true
    ).

    SUBMIT (lv_submit_prog) USING SELECTION-SET lv_submit_vari AND RETURN.

    " --- 5. Retrieve Data ---
    TRY.
        cl_salv_bs_runtime_info=>get_data_ref( IMPORTING r_data = lr_data ).
        ASSIGN lr_data->* TO <lt_alv_data>.
      CATCH cx_salv_bs_sc_runtime_info.
        WRITE: / 'Warning: Program', lv_submit_prog, 'did not return ALV data'.
        cl_salv_bs_runtime_info=>clear( ).
        CONTINUE.
    ENDTRY.

    " --- 6. Process Output Logic ---
    IF <lt_alv_data> IS ASSIGNED AND <lt_alv_data> IS NOT INITIAL.

      " Extract field mapping for the current program
      lt_mapping = VALUE #( FOR ls_m IN lt_zfir057at2
                             WHERE ( progname = lv_submit_prog AND variant = lv_submit_vari )
                             ( ls_m ) ).

      WRITE: / '-------------------------------------------'.
      WRITE: / 'Executing Program:', lv_submit_prog, ' Variant:', lv_submit_vari.

      TRY.
          lo_table_descr ?= cl_abap_tabledescr=>describe_by_data( <lt_alv_data> ).
          lo_struct_descr ?= lo_table_descr->get_table_line_type( ).
          lt_components = lo_struct_descr->get_components( ).

          LOOP AT lt_components INTO DATA(ls_comp).
            " Filter out all complex fields: 'Dynamic Address' and 'Nested Table' types
            IF ls_comp-type->type_kind = 'h' OR   " Internal Table
               ls_comp-type->type_kind = 's' OR   " Flat structure (needs expansion or deletion for DB)
               ls_comp-type->type_kind = 'u' OR   " Deep Structure (usually contains tables)
               ls_comp-type->type_kind = 'v' OR   " Data Reference
               ls_comp-type->type_kind = 'l'.     " Object Reference

              DELETE TABLE lt_components FROM ls_comp.
              CONTINUE.
            ENDIF.

            " Note:
            " 'g' (String) is kept -> maps to DB VARCHAR(MAX)
            " 'y' (XString) is kept -> maps to DB VARBINARY
          ENDLOOP.

          cl_salv_bs_runtime_info=>clear( ).

          IF ls_zfir057at1-zsfshowfield = 'X'.

            IF sy-mandt = '600' OR sy-mandt = '800'.
            ELSE.
              " 1. Define intermediate structure for ALV display
              TYPES: BEGIN OF ty_comp_output,
                       name          TYPE abap_compname,    " Field Name
                       type_kind     TYPE abap_typekind,    " Type
                       length        TYPE i,                " Length
                       decimals      TYPE i,                " Decimals
                       absolute_name TYPE string,           " Ref Dictionary Type
                     END OF ty_comp_output.
              DATA: lt_comp_output TYPE TABLE OF ty_comp_output.

              " 2. Extract metadata to intermediate table
              LOOP AT lt_components INTO ls_comp.
                APPEND INITIAL LINE TO lt_comp_output ASSIGNING FIELD-SYMBOL(<ls_out>).
                <ls_out>-name      = ls_comp-name.
                <ls_out>-type_kind = ls_comp-type->type_kind.
                <ls_out>-length    = ls_comp-type->length.
                <ls_out>-decimals  = ls_comp-type->decimals.

                " Clean the absolute path name
                <ls_out>-absolute_name = ls_comp-type->absolute_name.
                REPLACE FIRST OCCURRENCE OF '\TYPE=' IN <ls_out>-absolute_name WITH ''.
                REPLACE FIRST OCCURRENCE OF '\DATA=' IN <ls_out>-absolute_name WITH ''.
              ENDLOOP.

              " 3. Call SALV Popup for display
              DATA: lo_alv_comp TYPE REF TO cl_salv_table.
              TRY.
                  cl_salv_table=>factory(
                    IMPORTING
                      r_salv_table = lo_alv_comp
                    CHANGING
                      t_table      = lt_comp_output ).

                  " Set to Popup mode
                  lo_alv_comp->set_screen_popup(
                    start_column = 10
                    end_column   = 150
                    start_line   = 5
                    end_line     = 20 ).

                  " Enable basic functions (Search, Sort, Filter)
                  lo_alv_comp->get_functions( )->set_all( abap_true ).

                  " Modify Column Headers
                  DATA(lo_cols) = lo_alv_comp->get_columns( ).
                  lo_cols->set_optimize( abap_true ).
                  lo_cols->get_column( 'NAME' )->set_short_text( 'Field' ).
                  lo_cols->get_column( 'TYPE_KIND' )->set_short_text( 'Type' ).
                  lo_cols->get_column( 'LENGTH' )->set_short_text( 'Len(B)' ).
                  lo_cols->get_column( 'DECIMALS' )->set_short_text( 'Decimals' ).
                  lo_cols->get_column( 'ABSOLUTE_NAME' )->set_short_text( 'Dictionary' ).
                  
                  " Display
                  lo_alv_comp->display( ).

                CATCH cx_salv_msg.
                  MESSAGE 'Failed to call Metadata display popup' TYPE 'E'.
              ENDTRY.
            ENDIF.
          ENDIF.
        CATCH cx_root.
          WRITE: / 'Error: Dynamic structure parsing failed'.
      ENDTRY.

      " =====================================================================
      " [NEW] Dynamically insert ID, YEAR, MONTH at the beginning of lt_components
      " =====================================================================
      " 1. Prepare data type description objects
      DATA: lo_elem_id    TYPE REF TO cl_abap_elemdescr,
            lo_elem_year  TYPE REF TO cl_abap_elemdescr,
            lo_elem_month TYPE REF TO cl_abap_elemdescr.

      lo_elem_id    = cl_abap_elemdescr=>get_c( 32 ). " UUID C32

      IF ls_zfir057at1-zsfyearmonth = 'X'.
        lo_elem_year  = cl_abap_elemdescr=>get_c( 4 ).  " Year C4
        lo_elem_month = cl_abap_elemdescr=>get_c( 2 ).  " Month C2
      ENDIF.

      " 2. Insert into positions 1, 2, 3 in order
      INSERT VALUE #( name = 'ID'    type = lo_elem_id )    INTO lt_components INDEX 1.
      IF ls_zfir057at1-zsfyearmonth = 'X'..
        INSERT VALUE #( name = 'YEAR'  type = lo_elem_year )  INTO lt_components INDEX 2.
        INSERT VALUE #( name = 'MONTH' type = lo_elem_month ) INTO lt_components INDEX 3.
      ENDIF.

      IF lt_mapping IS NOT INITIAL.
        SORT lt_mapping BY sapfield.

        LOOP AT lt_components ASSIGNING FIELD-SYMBOL(<fs_component>).
          " 1. Skip Primary Key fields
          IF <fs_component>-name = 'ID' OR <fs_component>-name = 'YEAR' OR <fs_component>-name = 'MONTH'.
            CONTINUE.
          ENDIF.

          " 2. Look up Mapping Table
          READ TABLE lt_mapping INTO DATA(ls_mapping) WITH KEY sapfield = <fs_component>-name BINARY SEARCH.

          IF sy-subrc <> 0.
            " If no mapping found, delete current row
            DELETE lt_components INDEX sy-tabix.
            CONTINUE.
          ENDIF.

          " 3. Change Name (Modification affects internal table via Field Symbol)
          IF ls_mapping-zreplacefield = 'X'.
            <fs_component>-name = ls_mapping-non_sapfield.
          ENDIF.
        ENDLOOP.

        WRITE: / 'Output Mode: Partial fields automatic output'.
        PERFORM frm_crud_targetdata TABLES lt_components <lt_alv_data> USING ls_zfir057at1 .

      ELSE.
        " Case B: All fields automatic output
        WRITE: / 'Output Mode: All fields automatic output'.
        PERFORM frm_crud_targetdata TABLES lt_components <lt_alv_data> USING ls_zfir057at1 .

      ENDIF.

      " --- Cleanup within loop ---
      REFRESH lt_mapping.
      UNASSIGN <lt_alv_data>.
    ENDIF.

    " Ensure environment is cleared to prevent interference
    cl_salv_bs_runtime_info=>clear( ).

  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form frm_crud_targetdata
*&---------------------------------------------------------------------*
FORM frm_crud_targetdata TABLES lt_components   TYPE cl_abap_structdescr=>component_table
                                pt_table TYPE STANDARD TABLE
                          USING ps_zfir057at1   TYPE ts_zfir057at1.

  DATA: lv_target_tbname TYPE tabname.
  DATA: lt_val_tab TYPE TABLE OF rsparams.
  DATA: lv_where TYPE string.

  " Correct Type Name: Use system-standard TT_NAMED_SELTABS
  DATA: lt_shdb_seltables TYPE cl_shdb_seltab=>tt_named_seltables,
        ls_shdb_seltables LIKE LINE OF lt_shdb_seltables.

  DATA: lt_where_clauses TYPE TABLE OF string.

  IF ps_zfir057at1-tabname IS NOT INITIAL.
    lv_target_tbname = condense( ps_zfir057at1-tabname ).
  ENDIF.

  SELECT * FROM zfir057at3
    INTO TABLE @DATA(lt_zfir057at3)
    WHERE progname = @ps_zfir057at1-progname
      AND variant  = @ps_zfir057at1-variant.

  IF sy-subrc = 0.
    SORT lt_zfir057at3 BY sapfield.
    CALL FUNCTION 'RS_VARIANT_CONTENTS'
      EXPORTING
        report               = ps_zfir057at1-progname
        variant              = ps_zfir057at1-variant
      TABLES
        valutab              = lt_val_tab
      EXCEPTIONS
        variant_non_existent = 1
        variant_obsolete     = 2
        OTHERS               = 3.
    IF sy-subrc <> 0.
      " Suitable error handling
    ENDIF.

    LOOP AT lt_val_tab INTO DATA(ls_val_tab).
      " If not found in config, delete this query condition
      READ TABLE lt_zfir057at3 INTO DATA(ls_zfir057at3) WITH KEY sapfield = ls_val_tab-selname BINARY SEARCH.
      IF sy-subrc <> 0.
        DELETE TABLE lt_val_tab FROM ls_val_tab.
        CONTINUE.
      ENDIF.

      IF ls_val_tab-low IS INITIAL AND ls_val_tab-high IS INITIAL.
        DELETE TABLE lt_val_tab FROM ls_val_tab.
        CONTINUE.
      ENDIF.

      TYPES: tt_range_string TYPE RANGE OF string.

      IF ls_zfir057at3-reffiled IS NOT INITIAL.
        DATA: lr_ref_data TYPE REF TO data.
        TRY.
            " 1. Create dynamic variable based on Data Element in config table
            CREATE DATA lr_ref_data TYPE (ls_zfir057at3-reffiled).
            FIELD-SYMBOLS: <lv_ref_val> TYPE any.
            ASSIGN lr_ref_data->* TO <lv_ref_val>.

            " 2. Get true dictionary length
            DESCRIBE FIELD <lv_ref_val> LENGTH DATA(lv_len) IN CHARACTER MODE.

            " 3. Process LOW value
            IF ls_val_tab-low IS NOT INITIAL.
              DATA(lv_low_clean) = condense( ls_val_tab-low ). 

              IF ls_zfir057at3-sapconv = 'I'.
                " [SAP Standard I (Input)]: Pad leading zeros
                ls_val_tab-low = |{ lv_low_clean WIDTH = lv_len ALIGN = RIGHT PAD = '0' }|.
              ELSEIF ls_zfir057at3-sapconv = 'O'.
                " [SAP Standard O (Output)]: Remove leading zeros
                SHIFT lv_low_clean LEFT DELETING LEADING '0'.
                ls_val_tab-low = lv_low_clean.
              ENDIF.
            ENDIF.

            " 4. Process HIGH value
            IF ls_val_tab-high IS NOT INITIAL.
              DATA(lv_high_clean) = condense( ls_val_tab-high ).

              IF ls_zfir057at3-sapconv = 'I'.
                ls_val_tab-high = |{ lv_high_clean WIDTH = lv_len ALIGN = RIGHT PAD = '0' }|.
              ELSEIF ls_zfir057at3-sapconv = 'O'.
                SHIFT lv_high_clean LEFT DELETING LEADING '0'.
                ls_val_tab-high = lv_high_clean.
              ENDIF.
            ENDIF.

            " 5. Release memory
            IF <lv_ref_val> IS ASSIGNED.
              UNASSIGN <lv_ref_val>.
            ENDIF.
            CLEAR lr_ref_data.

          CATCH cx_sy_create_data_error.
            WRITE: / 'Warning: Dictionary type not found', ls_zfir057at3-reffiled.
        ENDTRY.
      ENDIF.

      IF ls_val_tab-kind = 'P'. " Parameter
        IF ls_val_tab-low IS NOT INITIAL.
          APPEND |{ ls_zfir057at3-dbfield } = '{ ls_val_tab-low }'| TO lt_where_clauses.
        ENDIF.
      ELSEIF ls_val_tab-kind = 'S'. " Select-Option

        IF ls_val_tab-low IS NOT INITIAL OR ls_val_tab-high IS NOT INITIAL.
          CLEAR ls_shdb_seltables.
          ls_shdb_seltables-name = ls_zfir057at3-dbfield.

          DATA: lr_range_table TYPE REF TO data.
          " Use custom standard Range type
          CREATE DATA lr_range_table TYPE tt_range_string.

          FIELD-SYMBOLS: <lt_range> TYPE tt_range_string.
          ASSIGN lr_range_table->* TO <lt_range>.

          APPEND VALUE #( sign   = ls_val_tab-sign
                          option = ls_val_tab-option
                          low    = ls_val_tab-low
                          high   = ls_val_tab-high ) TO <lt_range>.

          IF <lt_range> IS NOT INITIAL.
            ls_shdb_seltables-dref = lr_range_table.
            APPEND ls_shdb_seltables TO lt_shdb_seltables.
            CLEAR: ls_shdb_seltables.
          ENDIF.

          IF <lt_range> IS ASSIGNED.
            UNASSIGN <lt_range>.
          ENDIF.

          IF lt_shdb_seltables IS NOT INITIAL.
            TRY.
                " Call SQL conversion method
                DATA(lv_s_where) = cl_shdb_seltab=>combine_seltabs(
                  it_named_seltabs = lt_shdb_seltables
                ).

                IF lv_s_where IS NOT INITIAL.
                  APPEND lv_s_where TO lt_where_clauses.
                ENDIF.

              CATCH cx_shdb_exception.
                " SQL conversion exception handling
            ENDTRY.
          ENDIF.

          CLEAR: lt_shdb_seltables, lv_s_where.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF ps_zfir057at1-zsfyearmonth = 'X'.
      APPEND | YEAR = '{ sy-datum+0(4) }'| TO lt_where_clauses.
      APPEND | MONTH = '{ sy-datum+4(2) }'| TO lt_where_clauses.
    ENDIF.

    " Join all clauses with ' AND '
    IF lt_where_clauses IS NOT INITIAL.
      lv_where = concat_lines_of( table = lt_where_clauses sep = ' AND ' ).
    ENDIF.

    DATA: lo_new_struct_descr TYPE REF TO cl_abap_structdescr,
          lo_new_table_descr  TYPE REF TO cl_abap_tabledescr,
          lr_db_data          TYPE REF TO data. 

    FIELD-SYMBOLS: <lt_db> TYPE STANDARD TABLE. 

    TRY.
        " Step 1: Create dynamic structure description
        lo_new_struct_descr = cl_abap_structdescr=>create( p_components = lt_components[] ).

        " Step 2: Create dynamic table description
        lo_new_table_descr = cl_abap_tabledescr=>create( p_line_type = lo_new_struct_descr ).

        " Step 3: Allocate dynamic internal table space in memory
        CREATE DATA lr_db_data TYPE HANDLE lo_new_table_descr.

        " Step 4: Assign pointer for data access
        ASSIGN lr_db_data->* TO <lt_db>.

      CATCH cx_root INTO DATA(lx_rtts_err).
        WRITE: / 'Failed to generate dynamic table:', lx_rtts_err->get_text( ).
        RETURN.
    ENDTRY.

    " =======================================================================
    " 2. Combine ADBC (cl_sql_connection) to execute dynamic query with WHERE
    " =======================================================================
    DATA: go_db         TYPE REF TO cl_sql_connection,
          go_sqlerr_ref TYPE REF TO cx_sql_exception.

    TRY.
        " Connect to external DB (connection must be configured in DBCO)
        go_db = cl_sql_connection=>get_connection( ps_zfir057at1-dbname ).

        " Assemble native SELECT * SQL statement
        DATA(lv_stmt) = |SELECT * FROM { lv_target_tbname }|.
        IF lv_where IS NOT INITIAL.
          lv_stmt = |{ lv_stmt } WHERE { lv_where }|.
        ENDIF.

        " Create Statement and Execute
        DATA(lo_stmt_ref) = go_db->create_statement( tab_name_for_trace = lv_target_tbname ).
        DATA(lo_res_ref)  = lo_stmt_ref->execute_query( lv_stmt ).

        " Feed the dynamically generated lr_db_data to ADBC output table
        lo_res_ref->set_param_table( lr_db_data ).

        " Fetch data into memory
        DATA(lv_row_cnt) = lo_res_ref->next_package( ).

        " Close cursor to release resources
        lo_res_ref->close( ).

        WRITE: / 'Successfully fetched', lv_row_cnt, 'rows from external database'.

      CATCH cx_sql_exception INTO go_sqlerr_ref.
        MESSAGE go_sqlerr_ref->sql_message TYPE 'E'.
    ENDTRY.

    IF <lt_db> IS NOT INITIAL.
      " --- CRITICAL SAFETY CHECK: NEVER execute DELETE if WHERE is empty ---
      IF lv_target_tbname IS NOT INITIAL AND lv_where IS NOT INITIAL.

        TRY.
            " 1. Get external DB connection
            go_db = cl_sql_connection=>get_connection( ps_zfir057at1-dbname ).

            " 2. Concatenate complete DELETE SQL statement
            DATA(l_stmt_bulk_del) = |DELETE FROM { lv_target_tbname } WHERE { lv_where }|.

            " 3. Create Statement object
            DATA(l_stmt_ref_del) = go_db->create_statement( tab_name_for_trace = lv_target_tbname ).

            " 4. Execute bulk delete
            DATA(l_rows_deleted) = l_stmt_ref_del->execute_update( l_stmt_bulk_del ).

            " 5. Commit Transaction
            go_db->commit( ).

            WRITE: / 'Bulk delete successful, affected rows:', l_rows_deleted.

          CATCH cx_sql_exception INTO go_sqlerr_ref.
            " Core Fix: Catch exception during rollback
            IF go_db IS NOT INITIAL.
              TRY.
                  go_db->rollback( ).
                CATCH cx_sql_exception.
                  " Ignore exception during rollback
              ENDTRY.
            ENDIF.
            MESSAGE go_sqlerr_ref->sql_message TYPE 'E'.

          CATCH cx_parameter_invalid INTO DATA(lx_param).
            MESSAGE lx_param->get_text( ) TYPE 'E'.
        ENDTRY.

      ELSE.
        WRITE: / 'Warning: Table name or WHERE clause is empty. Bulk delete terminated to protect data!'.
      ENDIF.
    ENDIF.

    " ***** Prepare to write data to target database *****

    IF pt_table[] IS NOT INITIAL.

      " 1. Clear old data from SELECT, prepare to load new data
      CLEAR <lt_db>.

      " 2. Create single row pointer for mapping
      DATA: lr_db_row TYPE REF TO data.
      CREATE DATA lr_db_row TYPE HANDLE lo_new_struct_descr.
      FIELD-SYMBOLS: <ls_db_row> TYPE any.
      ASSIGN lr_db_row->* TO <ls_db_row>.

      " 3. Loop source data, precisely extract fields present in lt_components
      LOOP AT pt_table ASSIGNING FIELD-SYMBOL(<ls_pt_row>).
        CLEAR <ls_db_row>.

        LOOP AT lt_components INTO DATA(ls_comp_map).
          " Get value from ALV source row
          ASSIGN COMPONENT ls_comp_map-name OF STRUCTURE <ls_pt_row> TO FIELD-SYMBOL(<lv_src_val>).
          IF sy-subrc = 0.
            " Assign to target dynamic row
            ASSIGN COMPONENT ls_comp_map-name OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_val>).
            IF sy-subrc = 0.
              <lv_tgt_val> = <lv_src_val>.
            ENDIF.
          ENDIF.
        ENDLOOP.

        " --- Inject Dynamic Data (ID, YEAR, MONTH) ---
        " A. Generate 32-bit UUID
        TRY.
            DATA(lv_new_uuid) = cl_uuid_factory=>create_system_uuid( )->create_uuid_c32( ).
          CATCH cx_uuid_error.
            lv_new_uuid = sy-sysid && sy-datum && sy-uzeit. " Fallback logic
        ENDTRY.

        " B. Assign values to new fields in dynamic structure
        ASSIGN COMPONENT 'ID' OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_id>).
        IF sy-subrc = 0. <lv_tgt_id> = lv_new_uuid. ENDIF.

        IF ps_zfir057at1-zsfyearmonth = 'X'.
          ASSIGN COMPONENT 'YEAR' OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_year>).
          IF sy-subrc = 0. <lv_tgt_year> = sy-datum+0(4). ENDIF.

          ASSIGN COMPONENT 'MONTH' OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_month>).
          IF sy-subrc = 0. <lv_tgt_month> = sy-datum+4(2). ENDIF.
        ENDIF.

        APPEND <ls_db_row> TO <lt_db>.
      ENDLOOP.

      " 4. Assemble dynamic INSERT SQL statement
      IF <lt_db> IS NOT INITIAL.
        DATA: lt_fields TYPE TABLE OF string,
              lt_values TYPE TABLE OF string.

        LOOP AT lt_components INTO DATA(ls_comp_sql).
          APPEND ls_comp_sql-name TO lt_fields.
          APPEND '?' TO lt_values.
        ENDLOOP.

        DATA(lv_fields_str) = concat_lines_of( table = lt_fields sep = ',' ).
        DATA(lv_vals_str)   = concat_lines_of( table = lt_values sep = ',' ).

        DATA(lv_insert_sql) = |INSERT INTO { lv_target_tbname } ( { lv_fields_str } ) VALUES ( { lv_vals_str } )|.

        " 5. Execute ADBC Bulk Insert
        TRY.
            IF go_db IS INITIAL.
              go_db = cl_sql_connection=>get_connection( ps_zfir057at1-dbname ).
            ENDIF.

            DATA(lo_stmt_insert) = go_db->create_statement( tab_name_for_trace = lv_target_tbname ).

            " Bind the whole internal table
            lo_stmt_insert->set_param_table( lr_db_data ).

            " Execute bulk write
            DATA(lv_inserted_cnt) = lo_stmt_insert->execute_update( lv_insert_sql ).
            go_db->commit( ).

            WRITE: / 'Successfully written to target database, count:', lv_inserted_cnt.

          CATCH cx_sql_exception INTO DATA(lx_sql_ins).
            IF go_db IS NOT INITIAL.
              TRY.
                  go_db->rollback( ).
                CATCH cx_sql_exception.
              ENDTRY.
            ENDIF.
            MESSAGE lx_sql_ins->sql_message TYPE 'E'.

          CATCH cx_parameter_invalid INTO DATA(lx_param_ins).
            MESSAGE lx_param_ins->get_text( ) TYPE 'E'.
        ENDTRY.
      ENDIF.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form frm_fore_select_config
*& Description: In foreground mode, pop up zfir057at1 config table for 
*&              manual selection of programs to execute.
*&---------------------------------------------------------------------*
FORM frm_fore_select_config.

  DATA: lt_config TYPE TABLE OF zfir057at1,
        lo_alv    TYPE REF TO cl_salv_table.

  " 1. Get all non-blocked configurations
  SELECT * FROM zfir057at1
    INTO TABLE @lt_config
    WHERE zblock_push = ''.

  IF sy-subrc <> 0.
    MESSAGE 'No executable configuration records found!' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " 2. Pop up configuration table display
  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_config ).

      " Enable multiple selection and all toolbar functions
      lo_alv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>multiple ).
      lo_alv->get_functions( )->set_all( abap_true ).

      " Set as popup
      lo_alv->set_screen_popup( start_column = 10 end_column = 120 start_line = 5 end_line = 20 ).

      WRITE: / '>> Waiting for user to select configurations in the console...'.
      lo_alv->display( ).

      " 3. Get selected rows
      DATA(lt_sel_rows) = lo_alv->get_selections( )->get_selected_rows( ).

      IF lt_sel_rows IS INITIAL.
        WRITE: / '>> No configuration selected, operation cancelled.'.
        RETURN.
      ENDIF.

      " 4. Write selected data to global table gt_zfir057at1
      CLEAR gt_zfir057at1.
      LOOP AT lt_sel_rows INTO DATA(lv_row_idx).
        READ TABLE lt_config INTO DATA(ls_config) INDEX lv_row_idx.
        IF sy-subrc = 0.
          APPEND ls_config TO gt_zfir057at1.
        ENDIF.
      ENDLOOP.

      WRITE: / '>> User selected', lines( gt_zfir057at1 ), 'configurations. Starting execution...'.

      " 5. Seamlessly transition to main logic
      PERFORM frm_getdata_push.

    CATCH cx_salv_msg.
      WRITE: / 'Failed to generate configuration table popup'.
  ENDTRY.

ENDFORM.