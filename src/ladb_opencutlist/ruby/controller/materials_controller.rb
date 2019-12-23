module Ladb::OpenCutList

  require 'pathname'
  require 'securerandom'
  require_relative 'controller'
  require_relative '../model/material_attributes'
  require_relative '../utils/image_utils'

  class MaterialsController < Controller

    def initialize()
      super('materials')
    end

    def setup_commands()

      # Setup opencutlist dialog actions
      Plugin.instance.register_command("materials_list") do |settings|
        list_command(settings)
      end
      Plugin.instance.register_command("materials_create") do |material_data|
        create_command(material_data)
      end
      Plugin.instance.register_command("materials_update") do |material_data|
        update_command(material_data)
      end
      Plugin.instance.register_command("materials_remove") do |material_data|
        remove_command(material_data)
      end
      Plugin.instance.register_command("materials_import_from_skm") do ||
        import_from_skm_command
      end
      Plugin.instance.register_command("materials_export_to_skm") do |material_data|
        export_to_skm_command(material_data)
      end
      Plugin.instance.register_command("materials_get_attributes_command") do |material_data|
        get_attributes_command(material_data)
      end
      Plugin.instance.register_command("materials_get_texture_command") do |material_data|
        get_texture_command(material_data)
      end
      Plugin.instance.register_command("materials_add_std_dimension_command") do |settings|
        add_std_dimension_command(settings)
      end
      Plugin.instance.register_command("materials_set_current_command") do |settings|
        set_current_command(settings)
      end
      Plugin.instance.register_command("materials_purge_unused") do ||
        purge_unused_command
      end

    end

    private

    # -- Commands --

    def list_command(settings)

      # Check settings
      material_order_strategy = settings['material_order_strategy']

      model = Sketchup.active_model
      materials = model ? model.materials : nil

      temp_dir = Plugin.instance.temp_dir
      material_thumbnails_dir = File.join(temp_dir, 'material_thumbnails')
      if Dir.exist?(material_thumbnails_dir)
        FileUtils.remove_dir(material_thumbnails_dir, true)   # Temp dir exists we clean it
      end
      Dir.mkdir(material_thumbnails_dir)

      response = {
          :errors => [],
          :warnings => [],
          :filename => model && !model.path.empty? ? File.basename(model.path) : Plugin.instance.get_i18n_string('default.empty_filename'),
          :solid_wood_material_count => 0,
          :sheet_good_material_count => 0,
          :dimensional_material_count => 0,
          :edge_material_count => 0,
          :untyped_material_count => 0,
          :materials => [],
          :current_material_name => materials && materials.current ? materials.current.name : nil
      }

      if materials
        materials.each { |material|

          thumbnail_file = File.join(material_thumbnails_dir, "#{SecureRandom.uuid}.png")
          size = material.texture.nil? ? 8 : [ 128, material.texture.image_width - 1, material.texture.image_height - 1 ].min
          material.write_thumbnail(thumbnail_file, size)

          material_attributes = MaterialAttributes.new(material)

          response[:materials].push(
              {
                  :id => material.entityID,
                  :name => material.name,
                  :display_name => material.display_name,
                  :thumbnail_file => thumbnail_file,
                  :color => ("#%02x%02x%02x" % [material.color.red, material.color.green, material.color.blue]),
                  :alpha => material.alpha,
                  :colorized => material.materialType == 2, # 2 = Sketchup::Material::MATERIAL_COLORIZED_TEXTURED
                  :textured => (material.materialType == 1 or material.materialType == 2),  # 1 = Sketchup::Material::MATERIAL_TEXTURED, 2 = Sketchup::Material::MATERIAL_COLORIZED_TEXTURED
                  :texture_rotation => 0,
                  :texture_file => nil,
                  :texture_width => material.texture.nil? ? nil : material.texture.width.to_l.to_s,
                  :texture_height => material.texture.nil? ? nil : material.texture.height.to_l.to_s,
                  :texture_ratio => material.texture.nil? ? nil : material.texture.width / material.texture.height,
                  :texture_image_width => material.texture.nil? ? nil : material.texture.image_width,
                  :texture_image_height => material.texture.nil? ? nil : material.texture.image_height,
                  :texture_colorizable => Sketchup.version_number >= 16000000,
                  :texture_colorized => Sketchup.version_number < 16000000,
                  :attributes => {
                      :type => material_attributes.type,
                      :thickness => material_attributes.thickness,
                      :length_increase => material_attributes.length_increase,
                      :width_increase => material_attributes.width_increase,
                      :thickness_increase => material_attributes.thickness_increase,
                      :std_lengths => material_attributes.std_lengths,
                      :std_widths => material_attributes.std_widths,
                      :std_thicknesses => material_attributes.std_thicknesses,
                      :std_sections => material_attributes.std_sections,
                      :std_sizes => material_attributes.std_sizes,
                      :grained => material_attributes.grained,
                      :edge_decremented => material_attributes.edge_decremented,
                  }
              }
          )

          case material_attributes.type
            when MaterialAttributes::TYPE_SOLID_WOOD
              response[:solid_wood_material_count] += 1
            when MaterialAttributes::TYPE_SHEET_GOOD
              response[:sheet_good_material_count] += 1
            when MaterialAttributes::TYPE_DIMENSIONAL
              response[:dimensional_material_count] += 1
            when MaterialAttributes::TYPE_EDGE
              response[:edge_material_count] += 1
            else
              response[:untyped_material_count] += 1
          end
        }
      end

      # Errors
      if model
        if materials.count == 0
          response[:errors] << 'tab.materials.error.no_materials'
        end
      else
        response[:errors] << 'tab.materials.error.no_model'
      end

      # Sort materials
      response[:materials].sort! { |material_a, material_b| MaterialAttributes::material_order(material_a, material_b, material_order_strategy) }

      response
    end

    def create_command(material_data)

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      name = material_data['name']
      color = Sketchup::Color.new(material_data['color'])
      attributes = material_data['attributes']
      type = MaterialAttributes.valid_type(attributes['type'])
      thickness = attributes['thickness']
      length_increase = attributes['length_increase']
      width_increase = attributes['width_increase']
      thickness_increase = attributes['thickness_increase']
      std_lengths = attributes['std_lengths']
      std_widths = attributes['std_widths']
      std_thicknesses = attributes['std_thicknesses']
      std_sections = attributes['std_sections']
      std_sizes = attributes['std_sizes']
      grained = attributes['grained']
      edge_decremented = attributes['edge_decremented']

      materials = model.materials
      material = materials.add(name)
      material.color = color

      # Set attributes
      material_attributes = MaterialAttributes.new(material)
      material_attributes.type = type
      material_attributes.thickness = thickness
      material_attributes.length_increase = length_increase
      material_attributes.width_increase = width_increase
      material_attributes.thickness_increase = thickness_increase
      material_attributes.std_lengths = std_lengths
      material_attributes.std_widths = std_widths
      material_attributes.std_thicknesses = std_thicknesses
      material_attributes.std_sections = std_sections
      material_attributes.std_sizes = std_sizes
      material_attributes.grained = grained
      material_attributes.edge_decremented = edge_decremented
      material_attributes.write_to_attributes

      {
          :id => material.entityID,
      }
    end

    def update_command(material_data)

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      name = material_data['name']
      display_name = material_data['display_name']
      color = Sketchup::Color.new(material_data['color'])
      attributes = material_data['attributes']
      texture_rotation = material_data['texture_rotation']
      texture_file = material_data['texture_file']
      texture_width = material_data['texture_width']
      texture_height = material_data['texture_height']
      texture_colorizable = material_data['texture_colorizable']
      texture_colorized = material_data['texture_colorized']
      type = MaterialAttributes.valid_type(attributes['type'])
      thickness = attributes['thickness']
      length_increase = attributes['length_increase']
      width_increase = attributes['width_increase']
      thickness_increase = attributes['thickness_increase']
      std_lengths = attributes['std_lengths']
      std_widths = attributes['std_widths']
      std_thicknesses = attributes['std_thicknesses']
      std_sections = attributes['std_sections']
      std_sizes = attributes['std_sizes']
      grained = attributes['grained']
      edge_decremented = attributes['edge_decremented']

      # Fetch material
      materials = model.materials
      material = materials[name]

      if material

        trigger_change_event = true

        # Update properties
        if display_name != material.name

          material.name = display_name

          # In this case the event will be triggered by SU itself
          trigger_change_event = false

        end

        if color.to_i != material.color.to_i

          material.color = color

        end

        # Update texture
        unless texture_file.nil?

          if texture_rotation > 0 or (texture_colorized and texture_colorizable)

            # Rotate texture
            ImageUtils.rotate(texture_file, texture_rotation) if texture_rotation > 0

            # Keep previous material color if colorized material
            if !texture_colorized and material.materialType == 2 # 2 = Sketchup::Material::MATERIAL_COLORIZED_TEXTURED
              color = material.color
            else
              color = nil
            end

            # Set new texture to the material and re-apply previous color
            material.texture = texture_file

            # Re-apply color if colorized material
            if color
              material.color = color
            end

            # In this case the event will be triggered by SU itself
            trigger_change_event = false

          end

          unless texture_width.nil? or texture_height.nil?

            material.texture.size = [ DimensionUtils.instance.dd_to_ifloats(texture_width).to_l, DimensionUtils.instance.dd_to_ifloats(texture_height).to_l ]

            # In this case the event will be triggered by SU itself
            trigger_change_event = false

          end

        end

        # Update attributes
        material_attributes = MaterialAttributes.new(material)
        material_attributes.type = type
        material_attributes.thickness = thickness
        material_attributes.length_increase = length_increase
        material_attributes.width_increase = width_increase
        material_attributes.thickness_increase = thickness_increase
        material_attributes.std_lengths = std_lengths
        material_attributes.std_widths = std_widths
        material_attributes.std_thicknesses = std_thicknesses
        material_attributes.std_sections = std_sections
        material_attributes.std_sizes = std_sizes
        material_attributes.grained = grained
        material_attributes.edge_decremented = edge_decremented
        material_attributes.write_to_attributes

        # Trigger change event on materials observer if needed
        if trigger_change_event
          MaterialsObserver.instance.onMaterialChange(materials, material)
        end

      end

    end

    def remove_command(material_data)

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      name = material_data['name']

      response = {
          :errors => []
      }

      # Fetch material
      materials = model.materials
      material = materials[name]

      if material

        begin
          materials.remove(material)
        rescue => e
          response[:errors] << [ 'tab.materials.error.failed_removing_material', { :error => e.message } ]
        end

      else
        response[:errors] << [ 'tab.materials.error.failed_removing_material', { :error => '' }]
      end

      response
    end

    def import_from_skm_command

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      response = {
          :errors => []
      }

      # Fetch material
      materials = model.materials

      dir, filename = File.split(model.path)
      path = UI.openpanel(Plugin.instance.get_i18n_string('tab.materials.import_from_skm.title'), dir, "Material Files|*.skm;||")
      if path

        begin
          material = materials.load(path)
        rescue => e
          response[:errors] << [ 'tab.materials.error.failed_import_skm_file', { :error => e.message } ]
        end

      end

      response
    end

    def export_to_skm_command(material_data)

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      name = material_data['name']
      display_name = material_data['display_name']

      response = {
          :errors => [],
          :export_path => ''
      }

      # Fetch material
      materials = model.materials
      material = materials[name]

      if material

        dir, filename = File.split(model.path)
        path = UI.savepanel(Plugin.instance.get_i18n_string('tab.materials.export_to_skm.title'), dir, display_name + '.skm')
        if path
          begin
            unless File.directory?(dir)
              FileUtils.mkdir_p(dir)
            end
            material.save_as(path)
            response[:export_path] = path
          rescue => e
            response[:errors] << [ 'tab.materials.error.failed_export_skm_file', { :error => e.message } ]
          end
        end

      else
        response[:errors] << [ 'tab.materials.error.failed_export_skm_file', { :error => '' } ]
      end

      response
    end

    def get_attributes_command(material_data)

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      name = material_data['name']

      response = {
          :errors => [],
          :thickness => '',
          :length_increase => '',
          :width_increase => '',
          :thickness_increase => '',
          :std_lengths => [],
          :std_widths => [],
          :std_thicknesses => [],
          :std_sections => [],
          :std_sizes => [],
          :grained => false,
      }

      # Fetch material
      materials = model.materials
      material = materials[name]

      if material

        material_attributes = MaterialAttributes.new(material)

        response[:thickness] = material_attributes.thickness
        response[:length_increase] = material_attributes.length_increase
        response[:width_increase] = material_attributes.width_increase
        response[:thickness_increase] = material_attributes.thickness_increase
        response[:std_lengths] = material_attributes.std_lengths
        response[:std_widths] = material_attributes.std_widths
        response[:std_thicknesses] = material_attributes.std_thicknesses
        response[:std_section] = material_attributes.std_sections
        response[:std_sizes] = material_attributes.std_sizes
        response[:grained] = material_attributes.grained
        response[:edge_decremented] = material_attributes.edge_decremented

      end

      response
    end

    def get_texture_command(material_data)

      response = {
          :texture_file => '',
          :texture_colorized => false
      }

      model = Sketchup.active_model
      return response unless model

      name = material_data['name']
      colorized = material_data['colorized']

      # Fetch material
      materials = model.materials
      material = materials[name]

      if material

        temp_dir = Plugin.instance.temp_dir
        material_textures_dir = File.join(temp_dir, 'material_textures')
        if Dir.exist?(material_textures_dir)
          FileUtils.remove_dir(material_textures_dir, true)   # Temp dir exists we clean it
        end
        Dir.mkdir(material_textures_dir)

        texture_file = File.join(material_textures_dir, "#{SecureRandom.uuid}.png")

        if Sketchup.version_number >= 16000000

          material.texture.write(texture_file, colorized)

          response[:texture_colorized] = colorized

        else

          # Workaround to write texture to file from SU prior to 2016

          # Create a fake face
          model = Sketchup.active_model
          entities = model.active_entities
          group = entities.add_group
          pts = []
          pts[0] = [0, 0, 0]
          pts[1] = [1, 0, 0]
          pts[2] = [1, 1, 0]
          pts[3] = [0, 1, 0]
          face = group.entities.add_face(pts)
          face.material = material

          tw = Sketchup.create_texture_writer
          tw.load(face, true)
          tw.write(face, true, texture_file)

          # Erease the group
          group.erase!

          # This BC workaround force texture to be colorized
          response[:texture_colorized] = true

        end

        response[:texture_file] = texture_file
      end

      response
    end

    def add_std_dimension_command(settings) # Waiting settings = { :material_name => MATERIAL_NAME, :std_dimension => STD_DIMENSION }

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      material_name = settings['material_name']
      std_dimension = settings['std_dimension']

      # Fetch material
      materials = model.materials
      material = materials[material_name]

      if material

        material_attributes = MaterialAttributes.new(material)
        case material_attributes.type
          when MaterialAttributes::TYPE_SOLID_WOOD, MaterialAttributes::TYPE_SHEET_GOOD
            material_attributes.append_std_thickness(std_dimension)
          when MaterialAttributes::TYPE_DIMENSIONAL
            material_attributes.append_std_section(std_dimension)
          when MaterialAttributes::TYPE_EDGE
            material_attributes.append_std_width(std_dimension)
          else
            return { :errors => [ 'tab.materials.error.no_type_material' ] }
        end
        material_attributes.write_to_attributes

        # Trigger change event on materials observer
        MaterialsObserver.instance.onMaterialChange(materials, material)

      end

      { :success => true }
    end

    def set_current_command(settings)

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      name = settings['name']

      # Fetch material
      materials = model.materials
      material = materials[name]

      if material

        # Set material as current
        materials.current = material

        # Send action
        success = Sketchup.send_action('selectPaintTool:')

      end

      {
          :success => true,
      }
    end

    def purge_unused_command()

      model = Sketchup.active_model
      return { :errors => [ 'tab.materials.error.no_model' ] } unless model

      materials = model.materials
      materials.purge_unused

    end

  end

end