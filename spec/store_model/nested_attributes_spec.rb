# frozen_string_literal: true

require "spec_helper"

RSpec.describe StoreModel::NestedAttributes do
  let(:configuration_class) do
    Class.new do
      include StoreModel::Model

      attribute :color, :string
      attribute :suppliers, Supplier.to_array_type

      accepts_nested_attributes_for :suppliers
    end
  end

  let(:supplier1) { { title: "First" } }
  let(:supplier2) { { title: "Second" } }
  let(:attributes) { { color: "red", suppliers: [supplier1, supplier2] } }

  subject { configuration_class.new(attributes) }

  describe "#initialize" do
    context "when symbolized hash is passed" do
      it("assigns attributes to root model") do
        expect(subject).to have_attributes(attributes.slice(:color))
      end

      it("assigns attributes to nested model") do
        expect(subject.suppliers.first).to have_attributes(supplier1)
        expect(subject.suppliers.second).to have_attributes(supplier2)
      end
    end
  end

  describe "serializing nested json" do
    it "formats nested json as objects" do
      class ProductConfiguration
        include StoreModel::Model

        attribute :color, :string
        attribute :suppliers, Supplier.to_array_type

        accepts_nested_attributes_for :suppliers
      end

      class Product < ActiveRecord::Base
        attribute :configuration, ProductConfiguration.to_type, default: ProductConfiguration.new
      end

      suppliers = [Supplier.new(title: "The Supplier")]
      product = Product.create!(configuration: ProductConfiguration.new(color: "red", suppliers: suppliers))

      configuration_type = Product.select('json_type(configuration, "$") as config').where(id: product.id).first
      suppliers_type = Product.select('json_type(configuration, "$.suppliers") as config').where(id: product.id).first
      supplier_type = Product.select('json_type(configuration, "$.suppliers[0]") as config').where(id: product.id).first

      expect(configuration_type.config).to eq("object")
      expect(suppliers_type.config).to eq("array")
      expect(supplier_type.config).to eq("object")
    end

    context "when there are nested store_model attributes" do
      class NestedAndEncryptedAttrs < Anything
        class NestedStore
          include StoreModel::Model

          attribute :enc_val, Configuration::Encrypted.new
          attribute :non_enc_val
        end
        class Store
          include StoreModel::Model

          attribute :enc_val, Configuration::Encrypted.new
          attribute :non_enc_val
          attribute :nested, NestedStore.to_type
        end
        attribute :store, Store.to_type, default: -> { {} }
      end

      subject(:record) { NestedAndEncryptedAttrs.new(store: store) }

      let(:store) do
        { enc_val: "secret",
          non_enc_val: "public",
          nested: {
            enc_val: "nested secret",
            non_enc_val: "nested public"
          } }
      end

      let(:store_encrypted) do
        { enc_val: "vmhYmD",
          non_enc_val: "public",
          nested: {
            enc_val: "LmvDmq vmhYmD",
            non_enc_val: "nested public"
          } }
      end

      it "persists encrypted values" do
        record.save
        query = Anything.where(id: record.id).select(:id, :type, :store).to_sql
        _id, _type, store_persisted = ActiveRecord::Base.connection.query(query).first

        expect(store_persisted).to eq(store_encrypted.to_json)
        expect(JSON.parse(store_persisted).with_indifferent_access).to eq(store_encrypted.with_indifferent_access)
        expect(store_persisted).not_to include("secret")
        expect(store_persisted).to include("vmhYmD")
      end

      it "inner items can query with sql json syntax" do
        record.save
        very_nested_value = ActiveRecord::Base.connection.query(
          Anything.where(id: record.id).select("id, json_extract(store,'$.nested.non_enc_val')").to_sql
        ).first
        expect(very_nested_value).to eq([record.id, "nested public"])
      end
    end
  end

  describe "#as_json" do
    it "returns correct JSON" do
      expect(subject.as_json).to eq(attributes.as_json)
    end
  end

  describe "#accepts_nested_attributes_for" do
    let(:suppliers_attributes) { [supplier1, supplier2] }

    let(:attributes) do
      { color: "red", suppliers_attributes: suppliers_attributes }
    end

    it "assigns attributes to nested model" do
      expect(subject.suppliers.first).to have_attributes(supplier1)
      expect(subject.suppliers.second).to have_attributes(supplier2)
    end

    context "when attributes are passed as a hash instead of array of hashes" do
      let(:suppliers_attributes) { { "0" => supplier1, "1" => supplier2 } }

      it "assigns attributes to nested model" do
        expect(subject.suppliers.first).to have_attributes(supplier1)
        expect(subject.suppliers.second).to have_attributes(supplier2)
      end
    end

    context "when association is singular" do
      let(:configuration_class) do
        Class.new do
          include StoreModel::Model

          attribute :color, :string
          attribute :supplier, Supplier.to_type

          accepts_nested_attributes_for :supplier
        end
      end

      let(:attributes) { { color: "red", supplier_attributes: supplier1 } }

      it("assigns attributes to root model") do
        expect(subject).to have_attributes(attributes.slice(:color))
      end

      it("assigns attributes to nested model") do
        expect(subject.supplier).to have_attributes(supplier1)
      end

      context "and allow_destroy is true" do
        let(:configuration_class) do
          Class.new do
            include StoreModel::Model

            attribute :color, :string
            attribute :supplier, Supplier.to_type

            accepts_nested_attributes_for :supplier, allow_destroy: true
          end
        end

        before { supplier1[:_destroy] = _destroy }
        let(:_destroy) { "0" }

        context "and _destroy is 1" do
          let(:_destroy) { "1" }

          it("does not assign attributes to nested model") do
            expect(subject.supplier).to be_nil
          end
        end

        context "and _destroy is 0" do
          let(:_destroy) { "0" }

          it("assigns attributes to nested model") do
            expect(subject.supplier).to have_attributes(supplier1.except(:_destroy))
          end
        end

        it "defines _destroy attribute" do
          expect(subject.supplier).to respond_to(:_destroy)
          expect(subject.supplier).to respond_to(:_destroy=)
        end
      end
    end

    context "when allow_destroy is true" do
      let(:configuration_class) do
        Class.new do
          include StoreModel::Model

          attribute :color, :string
          attribute :suppliers, Supplier.to_array_type

          accepts_nested_attributes_for :suppliers, allow_destroy: true
        end
      end

      before { supplier1[:_destroy] = _destroy }
      let(:_destroy) { "0" }

      it "defines _destroy attribute" do
        expect(subject.suppliers.first).to respond_to(:_destroy)
        expect(subject.suppliers.first).to respond_to(:_destroy=)
      end

      context "and _destroy is 1" do
        let(:_destroy) { "1" }

        it "assigns only supplier2" do
          expect(subject.suppliers).to contain_exactly(
            have_attributes(supplier2)
          )
        end
      end

      context "and _destroy is 0" do
        let(:_destroy) { "0" }

        it "assigns attributes to nested model" do
          expect(subject.suppliers).to contain_exactly(
            have_attributes(supplier1.except(:_destroy)),
            have_attributes(supplier2)
          )
        end
      end
    end

    context "when reject_if is a proc" do
      let(:configuration_class) do
        Class.new do
          include StoreModel::Model

          attribute :color, :string
          attribute :suppliers, Supplier.to_array_type

          accepts_nested_attributes_for :suppliers, reject_if: ->(attributes) { attributes["title"].blank? }
        end
      end

      let(:blank_supplier) { { "title" => "" } }
      let(:present_supplier) { { "title" => "foo" } }
      let(:suppliers_attributes) { [blank_supplier, present_supplier] }

      subject { configuration_class.new(suppliers_attributes: suppliers_attributes) }

      it "rejects any attributes hash that returns true from the proc" do
        expect(subject.suppliers).to contain_exactly(
          have_attributes(present_supplier)
        )
      end
    end

    context "when reject_if is a symbol" do
      let(:configuration_class) do
        Class.new do
          include StoreModel::Model

          attribute :color, :string
          attribute :suppliers, Supplier.to_array_type

          accepts_nested_attributes_for :suppliers, reject_if: :reject_supplier

          def reject_supplier(attributes)
            attributes["title"].blank?
          end
        end
      end

      let(:blank_supplier) { { "title" => "" } }
      let(:present_supplier) { { "title" => "foo" } }
      let(:suppliers_attributes) { [blank_supplier, present_supplier] }

      subject { configuration_class.new(suppliers_attributes: suppliers_attributes) }

      it "rejects any attributes hash that returns true from the method" do
        expect(subject.suppliers).to contain_exactly(
          have_attributes(present_supplier)
        )
      end
    end

    context "when reject_if is :all_blank" do
      let(:configuration_class) do
        Class.new do
          include StoreModel::Model

          attribute :color, :string
          attribute :suppliers, Supplier.to_array_type

          accepts_nested_attributes_for :suppliers, reject_if: :all_blank
        end
      end

      let(:blank_supplier) { { "title" => "" } }
      let(:present_supplier) { { "title" => "foo" } }
      let(:suppliers_attributes) { [blank_supplier, present_supplier] }

      subject { configuration_class.new(suppliers_attributes: suppliers_attributes) }

      it "rejects any attributes hash that has all blank values" do
        expect(subject.suppliers).to contain_exactly(
          have_attributes(present_supplier)
        )
      end
    end
  end

  describe "#valid?" do
    let(:child_class) do
      Class.new do
        def self.model_name
          ActiveModel::Name.new(self, nil, "FormInput")
        end

        include StoreModel::Model

        attribute :data, :string

        validates :data, presence: true
      end
    end

    let(:parent_class) do
      children_type = child_class.to_array_type

      Class.new do
        def self.model_name
          ActiveModel::Name.new(self, nil, "Form")
        end

        include StoreModel::Model

        attribute :children, children_type

        validates :children, store_model: true
      end
    end

    context "when child model is invalid" do
      subject { parent_class.new(children: [child_class.new]) }

      it { is_expected.to be_invalid }
    end
  end

  context "when mixed in to an activerecord model" do
    let(:model_class) { Store }

    describe "#accepts_nested_attributes_for" do
      context "with standard rails syntax" do
        subject do
          model_class.accepts_nested_attributes_for(:products, allow_destroy: true)
          model_class.new
        end

        it { is_expected.to respond_to(:products_attributes=) }
      end

      context "allows mixing associations with attributes" do
        subject do
          model_class.attribute :bicycles, Bicycle.to_array_type
          model_class.accepts_nested_attributes_for(:products, :bicycles, allow_destroy: true)
          model_class.new
        end

        it { is_expected.to respond_to(:products_attributes=) }
        it { is_expected.to respond_to(:bicycles_attributes=) }
      end

      context "when db is not connected" do
        subject do
          model_class.accepts_nested_attributes_for(:suppliers)
          model_class
        end

        let(:model_class) do
          Class.new(ActiveRecord::Base) do
            include StoreModel::NestedAttributes

            def self.name
              "invalid_table_name"
            end

            attribute :suppliers, Supplier.to_array_type
          end
        end

        it { expect { subject }.not_to(raise_error) }
        it { expect(subject.instance_methods).to(include(:suppliers_attributes=)) }
      end
    end
  end
end
