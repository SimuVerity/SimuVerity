function struct_out = structDouble2Single( struct_in )
field_names = fieldnames( struct_in );
for i = 1:length(field_names)
    current_field = struct_in.( field_names{i} );
    if isa( current_field, 'struct' )
        struct_out.( field_names{i} ) = structDouble2Single( struct_in.( field_names{i} ) );
    elseif isa( current_field, 'double' )
        struct_out.( field_names{i} ) = single( struct_in.( field_names{i} ) );
    else
        struct_out.( field_names{i} ) = struct_in.( field_names{i} );
    end
end

end
