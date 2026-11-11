package cn.workpanel.module.personaltodo;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import java.sql.*;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

/** Upgrade a disposable schema from the inspected main V23; never repair published history. */
class TodoMigrationUpgradeTest {
    @Test void upgradesExistingMainAndPreservesUsers()throws Exception{
        String url=System.getenv().getOrDefault("DB_URL","jdbc:postgresql://127.0.0.1:55432/workpanel");
        String user=System.getenv().getOrDefault("DB_USER","workpanel"),password=System.getenv().getOrDefault("DB_PASSWORD","");
        String schema="todo_upgrade_"+UUID.randomUUID().toString().replace("-","");
        try(var c=DriverManager.getConnection(url,user,password);var sql=c.createStatement()){
            sql.execute("CREATE SCHEMA "+schema);
            try {
                Flyway.configure().dataSource(url,user,password).schemas(schema).defaultSchema(schema).target("23").load().migrate();
                sql.execute("SET search_path TO "+schema);
                sql.execute("INSERT INTO companies(id,name) VALUES ('upgrade-company','upgrade')");
                sql.execute("INSERT INTO users(id,company_id,account,password_hash,name,phone,role,status) VALUES ('upgrade-owner','upgrade-company','upgrade-owner','x','owner','upgrade-phone','EMPLOYEE','ACTIVE')");
                Flyway.configure().dataSource(url,user,password).schemas(schema).defaultSchema(schema).load().migrate();
                sql.execute("INSERT INTO personal_todos(id,company_id,owner_id,business_date,end_date,title) VALUES ('todo','upgrade-company','upgrade-owner','2028-02-29','2028-02-29','private')");
                try(var rows=sql.executeQuery("SELECT count(*) FROM users WHERE id='upgrade-owner'")){rows.next();assertEquals(1,rows.getInt(1));}
                try(var rows=sql.executeQuery("SELECT version FROM personal_todos WHERE id='todo'")){rows.next();assertEquals(1,rows.getInt(1));}
                Flyway.configure().dataSource(url,user,password).schemas(schema).defaultSchema(schema).load().validate();
            } finally {sql.execute("SET search_path TO public");sql.execute("DROP SCHEMA "+schema+" CASCADE");}
        }
    }
}
