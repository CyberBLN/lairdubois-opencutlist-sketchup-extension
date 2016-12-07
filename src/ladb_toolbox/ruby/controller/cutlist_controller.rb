require 'pathname'
require_relative 'controller'
require_relative '../model/size'
require_relative '../model/cutlist'
require_relative '../model/groupdef'
require_relative '../model/piecedef'

class CutlistController < Controller

  def initialize(plugin)
    super(plugin)
  end

  def setup_dialog_actions(dialog)

    # Setup toolbox dialog actions
    dialog.add_action_callback("ladb_cutlist_generate") do |action_context, json_params|

      params = JSON.parse(json_params)

      # Explode parameters
      length_increase = params['length_increase'].to_l
      width_increase = params['width_increase'].to_l
      thickness_increase = params['thickness_increase'].to_l
      piece_number_sequence_by_group = params['piece_number_sequence_by_group']
      piece_number_letter = params['piece_number_letter']

      # Generate cutlist
      json_data = generate_cutlist(
          length_increase,
          width_increase,
          thickness_increase,
          piece_number_sequence_by_group,
          piece_number_letter
      )

      # Callback to JS
      dialog.execute_script("$('#ladb_tab_cutlist').ladbTabCutlist('onCutlistGenerated', '#{json_data}')")

    end

  end

  private

  def _fetch_leafs(entity, leaf_components)
    child_component_count = 0
    if entity.visible? and entity.layer.visible?
      if entity.is_a? Sketchup::Group
        entity.entities.each { |child_entity|
          child_component_count += _fetch_leafs(child_entity, leaf_components)
        }
      elsif entity.is_a? Sketchup::ComponentInstance
        entity.definition.entities.each { |child_entity|
          child_component_count += _fetch_leafs(child_entity, leaf_components)
        }
        if child_component_count == 0
          leaf_components.push(entity)
          return 1
        end
      end
    end
    child_component_count
  end

  def _compute_faces_bounds(definition)
    bounds = Geom::BoundingBox.new
    definition.entities.each { |entity|
      if entity.is_a? Sketchup::Face
        bounds.add(entity.bounds)
      end
    }
    bounds
  end

  def _size_from_bounds(bounds)
    ordered = [bounds.width, bounds.height, bounds.depth].sort
    Size.new(ordered[2], ordered[1], ordered[0])
  end

  def _convert_to_std_thickness(thickness)
    std_thicknesses = ['18mm'.to_l, '27mm'.to_l, '35mm'.to_l, '45mm'.to_l, '65mm'.to_l, '80mm'.to_l, '100mm'.to_l]
    std_thicknesses.each { |std_thickness|
      if thickness <= std_thickness
        return std_thickness;
      end
    }
    thickness
  end

  def _sanitize_string(str)
    if str
      str
          .downcase
          .gsub(/^.*(\\|\/)/, '')
          .gsub!(/[^0-9A-Za-z.\-]/, '_')
    end
  end

  public

  def generate_cutlist(length_increase, width_increase, thickness_increase, piece_number_sequence_by_group, piece_number_letter)

    # Retrieve selected entities or all if no selection
    model = Sketchup.active_model
    if model.selection.empty?
      entities = model.active_entities
      use_selection = false
    else
      entities = model.selection
      use_selection = true
    end

    # Fetch leaf components in given entities
    leaf_components = []
    entities.each { |entity|
      _fetch_leafs(entity, leaf_components)
    }

    status = Cutlist::STATUS_SUCCESS
    filename = Pathname.new(Sketchup.active_model.path).basename
    length_unit = Sketchup.active_model.options['UnitsOptions']['LengthUnit']

    # Create cut list
    cutlist = Cutlist.new(status, filename, length_unit)

    # Errors
    if leaf_components.length == 0
      if use_selection
        cutlist.add_error("Auncune instance de composant na été détectée dans votre sélection")
      else
        cutlist.add_error("Auncune instance de composant na été détectée sur votre scène")
      end
    end

    # Populate cutlist
    leaf_components.each { |component|

      material = component.material
      definition = component.definition

      material_name = material ? component.material.name : '[Matière non définie]'

      size = _size_from_bounds(_compute_faces_bounds(definition))
      raw_size = Size.new(
          (size.length + length_increase).to_l,
          (size.width + width_increase).to_l,
          _convert_to_std_thickness((size.thickness + thickness_increase).to_l)
      )

      key = material_name + ':' + raw_size.thickness.to_s
      group_def = cutlist.get_group_def(key)
      unless group_def

        group_def = GroupDef.new
        group_def.material_name = material_name
        group_def.raw_thickness = raw_size.thickness

        cutlist.set_group_def(key, group_def)

      end

      piece_def = group_def.get_piece_def(definition.name)
      unless piece_def

        piece_def = PieceDef.new
        piece_def.name = definition.name
        piece_def.raw_size = raw_size
        piece_def.size = size

        group_def.set_piece_def(definition.name, piece_def)

      end
      piece_def.count += 1
      piece_def.add_component_guid(component.guid)

      group_def.piece_count += 1

    }

    cutlist.to_json(piece_number_sequence_by_group, piece_number_letter)
  end

end