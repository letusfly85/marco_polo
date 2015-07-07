defmodule MarcoPoloTest do
  use ExUnit.Case, async: true

  alias MarcoPolo.Error

  test "start_link/1: not specifying a connection type raises an error" do
    msg = "no connection type (connect/db_open) specified"
    assert_raise ArgumentError, msg, fn ->
      MarcoPolo.start_link
    end
  end

  test "start_link/1: always returns {:ok, pid}" do
    assert {:ok, pid} = MarcoPolo.start_link(connection: :server)
    assert is_pid(pid)
  end

  test "db_exists?/3" do
    {:ok, c} = conn_server()
    assert {:ok, true}  = MarcoPolo.db_exists?(c, "MarcoPoloTest", "plocal")
    assert {:ok, false} = MarcoPolo.db_exists?(c, "nonexistent", "plocal")
  end

  test "create_db/4 with a database that doens't exist yet" do
    {:ok, c} = conn_server()
    assert :ok = MarcoPolo.create_db(c, "MarcoPoloTestGenerated", :document, :plocal)
  end

  test "create_db/4 with a database that already exists" do
    {:ok, c} = conn_server()

    assert {:error, %Error{} = err} = MarcoPolo.create_db(c, "MarcoPoloTest", :document, :plocal)
    assert [{exception, msg}] = err.errors
    assert exception == "com.orientechnologies.orient.core.exception.ODatabaseException"
    assert msg       =~ "Database named 'MarcoPoloTest' already exists:"
  end

  test "drop_db/3 with an existing database" do
    {:ok, c} = conn_server()
    assert :ok = MarcoPolo.drop_db(c, "MarcoPoloToDrop", :memory)
  end

  test "drop_db/3 with a non-existing database" do
    {:ok, c} = conn_server()

    expected = {"com.orientechnologies.orient.core.exception.OStorageException",
                "Database with name 'Nonexistent' doesn't exits."}

    assert {:error, %MarcoPolo.Error{} = err} = MarcoPolo.drop_db(c, "Nonexistent", :plocal)
    assert hd(err.errors) == expected
  end

  test "db_reload/1" do
    {:ok, c} = conn_db()
    assert :ok = MarcoPolo.db_reload(c)
  end

  test "db_size/1" do
    {:ok, c} = conn_db()
    assert {:ok, size} = MarcoPolo.db_size(c)
    assert is_integer(size)
  end

  test "db_countrecords/1" do
    {:ok, c} = conn_db()
    assert {:ok, nrecords} = MarcoPolo.db_countrecords(c)
    assert is_integer(nrecords)
  end

  test "load_record/4" do
    {:ok, c} = conn_db()

    rid = TestHelpers.record_rid("record_load")

    {:ok, [record]} = MarcoPolo.load_record(c, rid, "*:-1")

    assert %MarcoPolo.Record{} = record
    assert record.version == 1
    assert record.class   == "Schemaless"
    assert record.fields  == %{"name" => "record_load"}

    rid = TestHelpers.record_rid("schemaless_record_load")

    {:ok, [record]} = MarcoPolo.load_record(c, rid, "*:-1")
    assert record.version == 1
    assert record.class == "Schemaful"
    assert record.fields == %{"myString" => "record_load"}
  end

  test "load_record/4 using the :if_version_not_latest option" do
    {:ok, c} = conn_db()
    rid      = TestHelpers.record_rid("record_load")

    assert {:ok, []} = MarcoPolo.load_record(c, rid, "*:-1", version: 1, if_version_not_latest: true)
  end

  test "delete_record/3" do
    {:ok, c} = conn_db()
    version  = 1
    rid      = TestHelpers.record_rid("record_delete")

    # Wrong version causes no deletions.
    assert {:ok, false} = MarcoPolo.delete_record(c, rid, version + 100)

    assert {:ok, true}  = MarcoPolo.delete_record(c, rid, version)
    assert {:ok, false} = MarcoPolo.delete_record(c, rid, version)
  end

  test "create_record/3" do
    {:ok, c} = conn_db()
    cluster_id = TestHelpers.cluster_id("schemaless")
    record = %MarcoPolo.Record{class: "Schemaless", fields: %{"foo" => "bar"}}

    {:ok, {rid, version}} = MarcoPolo.create_record(c, cluster_id, record)

    assert %MarcoPolo.RID{cluster_id: ^cluster_id} = rid
    assert is_integer(version)
  end

  test "command/3: SELECT query without a WHERE clause" do
    {:ok, c}       = conn_db()
    {:ok, records} = MarcoPolo.command(c, "SELECT FROM Schemaless", fetch_plan: "*:-1")

    assert Enum.find(records, fn record ->
      assert %MarcoPolo.Record{} = record
      assert record.class == "Schemaless"

      record.fields["name"] == "record_load"
    end)
  end

  test "command/3: SELECT query with a WHERE clause" do
    {:ok, c} = conn_db()

    cmd = "SELECT FROM Schemaless WHERE name = 'record_load' LIMIT 1"
    res = MarcoPolo.command(c, cmd, fetch_plan: "*:-1")

    assert {:ok, [%MarcoPolo.Record{} = record]} = res
    assert record.fields["name"] == "record_load"
  end

  test "command/3: SELECT query with a WHERE clause and parameters" do
    {:ok, c} = conn_db()

    cmd    = "SELECT FROM Schemaless WHERE name = :name"
    params = %{"name" => "record_load"}
    res    = MarcoPolo.command(c, cmd, fetch_plan: "*:-1", params: params)

    assert {:ok, [%MarcoPolo.Record{} = record]} = res
    assert record.fields["name"] == "record_load"
  end

  test "command/3: INSERT query inserting multiple records" do
    {:ok, c} = conn_db()
    cmd = "INSERT INTO Schemaless(my_field) VALUES ('value1'), ('value2')"

    assert {:ok, [r1, r2]} = MarcoPolo.command(c, cmd)
    assert r1.fields["my_field"] == "value1"
    assert r2.fields["my_field"] == "value2"
  end

  test "command/3: UPDATE query with parameters" do
    {:ok, c} = conn_db()
    cmd = "UPDATE Schemaless SET f = :f WHERE name = :name"
    params = %{"name" => "record_update", "f" => "new_value"}

    # TODO the response is a binary dump with "1" in it, not sure what that
    # means.
    assert {:ok, "1"} = MarcoPolo.command(c, cmd, params: params)
  end

  test "command/3: miscellaneous commands" do
    import MarcoPolo, only: [command: 2, command: 3]

    {:ok, c} = conn_db()

    assert {:ok, _cluster} = command(c, "CREATE CLUSTER misc_tests")
    assert {:ok, _cluster} = command(c, "CREATE CLASS MiscTests CLUSTER misc_tests")
    assert {:ok, _unknown} = command(c, "CREATE PROPERTY MiscTests.foo DATETIME")
    assert {:ok, nil}      = command(c, "DROP PROPERTY MiscTests.foo")
    assert {:ok, "true"}   = command(c, "DROP CLASS MiscTests")
    assert {:ok, "true"}   = command(c, "DROP CLUSTER misc_tests")
    assert {:ok, "false"}  = command(c, "DROP CLUSTER misc_tests")
  end

  test "command/3 and fetch_schema/1: unknown property id" do
    import MarcoPolo, only: [command: 2, command: 3]

    insert_query = "INSERT INTO UnknownPropertyId(i) VALUES (30)"

    {:ok, c} = conn_db()
    {:ok, _} = command(c, "CREATE CLASS UnknownPropertyId")
    {:ok, _} = command(c, "CREATE PROPERTY UnknownPropertyId.i SHORT")

    assert {:error, :unknown_property_id} = command(c, insert_query)

    :ok = MarcoPolo.fetch_schema(c)

    assert {:ok, %MarcoPolo.Record{} = record} = command(c, insert_query)
    assert record.class   == "UnknownPropertyId"
    assert record.version == 1
    assert record.fields  == %{"i" => 30}
  end

  defp conn_server do
    MarcoPolo.start_link(connection: :server,
                         user: TestHelpers.user(),
                         password: TestHelpers.password())
  end

  defp conn_db do
    MarcoPolo.start_link(connection: {:db, "MarcoPoloTest", "plocal"},
                         user: TestHelpers.user(),
                         password: TestHelpers.password())
  end
end
