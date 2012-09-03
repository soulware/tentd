require 'spec_helper'

describe TentServer::API::Profile do
  def app
    TentServer::API.new
  end

  let(:entity) { 'https://smith.example.org' }
  let(:env) { { 'tent.entity' => entity } }
  let(:params) { Hash.new }

  let(:authorized_info_types) { [] }
  let(:authorized_scopes) { [] }
  let(:app_authorization) do
    Fabricate(
      :app_authorization,
      :app => Fabricate(:app),
      :profile_info_types => authorized_info_types,
      :scopes => authorized_scopes
    )
  end

  let(:basic_info_type) { "https://tent.io/types/info/basic" }
  let(:basic_info_content) do
    {
      "name" => "John Smith",
      "age" => 21
    }
  end

  let(:work_history_type) { "https://tent.io/types/info/work-history" }
  let(:work_history_content) do
    {
      "employers" => ["Foo Corp"]
    }
  end

  def url_encode_type(type)
    URI.encode(type, ":/")
  end

  def create_info(type, content, options = {})
    Fabricate(:profile_info, :public => options[:public], :entity => entity, :type => type, :content => content)
  end

  describe 'GET /profile' do
    context 'when read_profile scope authorized' do
      let(:authorized_scopes) { [:read_profile] }
      before { env['current_auth'] = app_authorization }

      context 'when authorized for all info types' do
        let(:authorized_info_types) { ['all'] }

        it 'should return all info types' do
          TentServer::Model::ProfileInfo.all.destroy

          profile_infos = []
          profile_infos << Fabricate(:profile_info, :public => false, :entity => entity, :tent => true)
          profile_infos << Fabricate(:profile_info, :public => false, :entity => entity)

          json_get '/profile', params, env
          expect(last_response.body).to eq({
            "#{ profile_infos.first.type }" => profile_infos.first.content,
            "#{ profile_infos.last.type }" => profile_infos.last.content
          }.to_json)
        end
      end

      context 'when authorized for specific info types' do
        let(:authorized_info_types) { ['https://tent.io/types/info/basic-info'] }

        it 'should only return authorized info types' do
          TentServer::Model::ProfileInfo.all.destroy

          profile_infos = []
          profile_infos << Fabricate(:profile_info, :public => false, :entity => entity, :type => "https://tent.io/types/info/basic-info")
          profile_infos << Fabricate(:profile_info, :public => false, :entity => entity)

          json_get '/profile', params, env
          expect(last_response.body).to eq({
            "#{ profile_infos.first.type }" => profile_infos.first.content
          }.to_json)
        end
      end
    end

    context 'when read_profile scope unauthorized' do
      it 'should only return public profile into types' do
        TentServer::Model::ProfileInfo.all.destroy

        profile_infos = []
        profile_infos << Fabricate(:profile_info, :public => true, :entity => entity, :tent => true)
        profile_infos << Fabricate(:profile_info, :public => false, :entity => entity)

        json_get '/profile', params, env
        expect(last_response.body).to eq({
          "#{ profile_infos.first.type }" => profile_infos.first.content
        }.to_json)
      end
    end
  end

  describe 'PUT /profile/:type_url' do
    before { env['current_auth'] = app_authorization }

    context 'when authorized' do
      let(:authorized_scopes) { [:write_profile] }

      can_update_basic_info_type = proc do
        it 'should update info type' do
          info = create_info(basic_info_type, basic_info_content, :public => false)

          data = {
            "name" => "John Doe"
          }

          json_put "/profile/#{url_encode_type(basic_info_type)}", data, env

          expect(info.reload.content).to eq(data)
          expect(last_response.status).to eq(200)
        end

        it 'should create unless exists' do
          TentServer::Model::ProfileInfo.all.destroy

          data = {
            "name" => "John Doe"
          }

          expect(lambda {
            json_put "/profile/#{url_encode_type(basic_info_type)}", data, env
          }).to change(TentServer::Model::ProfileInfo, :count).by(1)

          info = TentServer::Model::ProfileInfo.last
          expect(info.content).to eq(data)
          expect(last_response.status).to eq(200)
        end
      end

      context 'when all info types authorized' do
        let(:authorized_info_types) { ['all'] }

        context '', &can_update_basic_info_type
      end

      context 'when specific info types authorized' do
        context 'when :type_url authorized info type' do
          let(:authorized_info_types) { [basic_info_type] }

          context '', &can_update_basic_info_type
        end

        context 'when :type_url not authoried info type' do
          it 'should return 403' do
            json_put "/profile/#{url_encode_type(basic_info_type)}", params, env
            expect(last_response.status).to eq(403)
          end
        end
      end
    end

    context 'when not authorized' do
      it 'should return 403' do
        json_put "/profile/#{url_encode_type(basic_info_type)}", params, env
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'PATCH /profile' do
    before { env['current_auth'] = app_authorization }

    def diff_encode_type(type)
      type.gsub(/~/, '~0').gsub(/\//, '~1')
    end

    context 'when authorized' do
      let(:authorized_scopes) { [:write_profile] }

      can_update_basic_info_type = proc do
        it 'should update basic info with diff' do
          TentServer::Model::ProfileInfo.all.destroy

          info = create_info(basic_info_type, basic_info_content, :public => false)

          diff = [
            { "add" => "#{diff_encode_type(basic_info_type)}/city", "value" => "New York" },
            { "remove" => "#{diff_encode_type(basic_info_type)}/age" },
            { "replace" => "#{diff_encode_type(basic_info_type)}/name", "value" => "Alex Smith" }
          ]

          expected_data = {
            "city" => "New York",
            "name" => "Alex Smith",
          }

          json_patch "/profile", diff, env

          expect(last_response.status).to eq(200)
          expect(info.reload.content).to eq(expected_data)
        end

        it 'should return 422 if diff tests fail' do
          TentServer::Model::ProfileInfo.all.destroy

          info = create_info(basic_info_type, basic_info_content, :public => false)

          diff = [
            { "add" => "#{diff_encode_type(basic_info_type)}/city", "value" => "New York" },
            { "remove" => "#{diff_encode_type(basic_info_type)}/age" },
            { "replace" => "#{diff_encode_type(basic_info_type)}/name", "value" => "Alex Smith" },
            { "test" => "#{diff_encode_type(basic_info_type)}/age", "value" => 40 },
          ]

          expected_data = info.content

          json_patch "/profile", diff, env

          expect(last_response.status).to eq(422)
          expect(info.reload.content).to eq(expected_data)
        end
      end

      context 'when all info types authorized' do
        let(:authorized_info_types) { ['all'] }

        context '', &can_update_basic_info_type
        
        it 'should update any info' do
          TentServer::Model::ProfileInfo.all.destroy

          info = create_info(basic_info_type, basic_info_content, :public => false)

          diff = [
            { "add" => "#{diff_encode_type(basic_info_type)}/city", "value" => "New York" },
            { "remove" => "#{diff_encode_type(basic_info_type)}/age" },
            { "replace" => "#{diff_encode_type(basic_info_type)}/name", "value" => "Alex Smith" },
            { "add" => "#{diff_encode_type(work_history_type)}/employers", "value" => ["Foo Corp"] },
            { "move" => "#{diff_encode_type(basic_info_type)}/name", "to" => "#{diff_encode_type(work_history_type)}/name" },
            { "add" => "#{diff_encode_type(work_history_type)}/employers/1", "value" => "Bar Corp" },
            { "add" => "#{diff_encode_type(work_history_type)}/city", "value" => "London" }
          ]

          expected_basic_data = {
            "city" => "New York",
          }

          expected_work_data = {
            "name" => "Alex Smith",
            "employers" => ["Foo Corp", "Bar Corp"],
            "city" => "London"
          }

          expect(lambda {
            json_patch "/profile", diff, env
          }).to change(TentServer::Model::ProfileInfo, :count).by(1)

          expect(last_response.status).to eq(200)
          expect(info.reload.content).to eq(expected_basic_data)

          work_info = TentServer::Model::ProfileInfo.last
          expect(work_info.content).to eq(expected_work_data)
        end
      end

      context 'when specific info types authorized' do
        let(:authorized_info_types) { [basic_info_type] }

        context '', &can_update_basic_info_type
      end
    end

    context 'when not authorized' do
      it 'should return 403' do
        json_patch '/profile', params, env
        expect(last_response.status).to eq(403)
      end
    end
  end
end
