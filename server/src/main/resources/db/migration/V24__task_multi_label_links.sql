-- V21 的单任务标签关联升级为可选的去重集合；历史单标签记录自然保留为一个元素。
ALTER TABLE task_label_links DROP CONSTRAINT task_label_links_pkey;
ALTER TABLE task_label_links ADD CONSTRAINT task_label_links_pkey PRIMARY KEY(task_id,label_id);
