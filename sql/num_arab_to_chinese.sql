create or replace function num2rmb(je number) return varchar2 is
	i pls_integer;
	snum varchar2(20) := ltrim(replace(to_char(abs(je), '9999999999999990.99'), '.'));
	len pls_integer := length(snum);
	sch varchar2(20) := '��Ҽ��������½��ƾ�';
	sjin varchar2(50) := '�ֽ�Բʰ��Ǫ��ʰ��Ǫ��ʰ��Ǫ��ʰ��Ǫ';
	srmb varchar2(100) := '';
	num pls_integer;
	s_num pls_integer := 0; --'0'��ʼλ��
	e_num pls_integer := 0; --'0'����λ��
begin
	for i in 1..len loop
		num := to_number(substr(snum, i, 1));
		if num <> 0 then --��'0'ʱ������
			if s_num = 0 then
				srmb := srmb || substr(sch, num + 1, 1) || substr(sjin, len - i + 1, 1); --ǰ���ַ���'0', ��������...
			else
				srmb := srmb || case --����
					when s_num = e_num then --ǰ��ֻ��һ��'0'
						case s_num
							when 7 then '��' --ֻ������λ
							when 11 then '��'
							when 15 then '��'
						end
					when e_num < 12 then --����(���'0'����)
						case
							when s_num < 7 then '' --������..
							when s_num < 11 then
								case
									when e_num < 8 and s_num < 10 then '��'
								end
							when s_num < 15 then
								case
									when e_num < 12 then '��'
								end
							else '����'
						end
					when e_num < 16 and s_num > 14 then '��'
				end || case
					when s_num > 3 and e_num < 3 then 'Բ��'
					when e_num = 3 then 'Բ'
					when e_num not in (7, 11, 15) or s_num - e_num > 2 then '��'
				end;
				srmb := srmb || substr(sch, num + 1, 1) || substr(sjin, len - i + 1, 1);
			end if;
			s_num := 0;
			e_num := 0;
		else
			if s_num = 0 then --��s_num = 0ʱ'0'����ʼ��
				s_num := len - i + 1; --��¼��ʼ
				e_num := s_num; --������λ�á�
			else
				e_num := len - i + 1; --�����µĽ���λ�á�
			end if;
		end if;
	end loop;
	if s_num <> 0 then --��ʱ��'0'��β
		srmb := srmb ||	case
			when s_num = len then '��Բ��' --ȫ'0'������...
			when s_num = 1 or s_num = 2 then '��' --��(1)����(2)���...
			when s_num < 7 or s_num = 10 then 'Բ��'
			when s_num < 11 then '��Բ��' 
			when s_num < 15 then '��Բ��'
			else '����Բ��'
		end;
	else
		srmb := srmb || '��'; --����'0'��β����...
	end if;
	if je < 0 then
		srmb:='��' || srmb;
	end if;
	return srmb;
end num2rmb;