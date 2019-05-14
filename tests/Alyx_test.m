classdef (SharedTestFixtures={matlab.unittest.fixtures.PathFixture(...
    [fileparts(mfilename('fullpath')) '\fixtures'])})... % add 'fixtures' folder as test fixture
    Alyx_test < matlab.unittest.TestCase
  % Test adapted from Oliver Winter's AlyxClient test
  
  properties % Test objects
    % Alyx Instance
    alyx
    % Test queue directory
    queueDir
    % Base URLs for various tests
    base = 'https://test.alyx.internationalbrainlab.org'
    % Login names for various tests
    uname = 'test_user'
    % Login passwords for various tests
    pwd = 'TapetesBloc18'
  end
  
  properties % Validation data
    subjects = {'IBL_46'; 'ZM_1085'; 'ZM_1087'; 'ZM_1094'; 'ZM_1098'; 'ZM_335'}
    water_types = {'Water', 'Hydrogel'}
    eids = {'cf264653-2deb-44cb-aa84-89b82507028a', ...
      '4e0b3320-47b7-416e-b842-c34dc9004cf8'}
  end
  
  methods (TestClassSetup)
    function checkFixtures(~)
      % Check we're using test paths file
      assert(endsWith(which('dat.paths'), fullfile('fixtures','+dat','paths.m')));
      % Check temp mainRepo folder is empty.  An extra safe measure as we
      % don't won't to delete important folders by accident!
      mainRepo = getOr(dat.paths, 'mainRepository');
      assert(~exist(mainRepo, 'dir') || isempty(setdiff(getOr(dir(mainRepo),'name'),{'.','..'})),...
        'Test experiment repo not empty.  Please set another path or manual empty folder');
    end
    
    function createObject(testCase)
      % Create a number of Alyx instances and log them in
      testCase.queueDir = fullfile(fileparts(mfilename('fullpath')),'fixtures','data');
      Alyx_test.resetQueue(testCase.queueDir); % Ensure empty before logging in
      
      testCase.water_types = {'Water', 'Water 15% Sucrose', ...
        'Citric Acid Water 2%', 'Hydrogel 5% Citric Acid', ...
        'Water 10% Sucrose', 'Water 2% Citric Acid', 'Hydrogel'};
      
      ai = Alyx('','');
      ai.BaseURL = testCase.base;
      ai.QueueDir = testCase.queueDir;
      ai = ai.login(testCase.uname, testCase.pwd);
      testCase.fatalAssertTrue(ai.IsLoggedIn, ...
        sprintf('Failed to log into %s', ai.BaseURL))
      testCase.alyx = ai;
      
      dataRepo = getOr(dat.paths, 'mainRepository');
      assert(exist(dataRepo, 'file') == 0 && exist(dataRepo, 'dir') == 0,...
        'Test data direcotry already exists.  Please remove and rerun tests')
      assert(mkdir(dataRepo), 'Failed to create test data directory');
    end
  end
  
  methods (TestMethodSetup)
    function testCase = methodSetup(testCase)
      testCase.fatalAssertTrue(all([testCase.alyx.Headless]==0) && ...
        all([testCase.alyx.IsLoggedIn]==1),...
        'Not all test instances connected')
      dataRepo = getOr(dat.paths, 'mainRepository');
      success = cellfun(@(d)mkdir(d), fullfile(dataRepo, testCase.subjects));
      assert(all(success), 'Failed to create tesst subject folders')
    end
  end
  
  methods(TestMethodTeardown)
    function methodTaredown(testCase)
      Alyx_test.resetQueue(testCase.queueDir);
      dataRepo = getOr(dat.paths, 'mainRepository');
      assert(rmdir(dataRepo, 's'), 'Failed to remove test data directory')
    end
  end
  
  methods(Test)
    
    function test_listSubjects(testCase)
      % Test that the subject list returned by the test database is
      % accurate
      ai = testCase.alyx(1);
      testCase.verifyTrue(isequal(ai.listSubjects, ...
        [{'default'}; testCase.subjects]), 'Subject list mismatch')
      
      % Test behaviour of empty list
      testCase.verifyTrue(strcmp('default', ai.listSubjects(1,1)),...
        'Subject list mismatch')
    end
    
    function test_makeEndPoint(testCase)
      % Test validation of base url and endpoints
      ai = testCase.alyx(1);
      sub = ai.getData('subjects/flowers');
      
      % Preceding slash
      sub2 = ai.getData('/subjects/flowers');
      testCase.verifyEqual(sub, sub2, 'Failed preceding slash test');
      
      % Trailing slash
      sub2 = ai.getData('subjects/flowers/');
      testCase.verifyEqual(sub, sub2, 'Failed preceding slash test');
      
      % Full endpoint URL
      sub2 = ai.getData([ai.BaseURL '/subjects/flowers']);
      testCase.verifyEqual(sub, sub2, 'Failed trailing slash test');
      
      % Test Base URL sanitizer
      ai.BaseURL = 'test.alyx.internationalbrainlab.org';
      base1 = ai.BaseURL;
      ai.BaseURL = 'https://test.alyx.internationalbrainlab.org/';
      base2 = ai.BaseURL;
      testCase.verifyEqual(base1, base2, 'BaseURL sanitizer test failed');
    end
    
    function test_getData(testCase)
      % Test retrieval from water-type endpoint
      ai = testCase.alyx(1);
      testCase.verifyTrue(isequal(testCase.water_types, ...
        {ai.getData('water-type').name}))
      
      % Test incorrect endpoint response
      testCase.verifyError(@()ai.getData('fail'), ...
        'MATLAB:webservices:HTTP404StatusCodeError');
      
      % Test invalid token
      ai = Alyx('test_user', 'bAdT0k3N');
      ai.Headless = true;
      testCase.verifyWarning(@()ai.getData('water-type'),...
        'Alyx:getData:InvalidToken');
      
      % Test timeout
      % TODO create webread mock for timeout test
      % Test incorrect URL
      % ai.BaseURL = 'https://notaurl';
      % FIXME what should be behaviour here?
    end
    
    function test_getSessions(testCase)
      ai = testCase.alyx(1);
      % Test subject search
      sess = ai.getSessions('subject', 'flowers');
      testCase.assertTrue(~isempty(sess), 'No sessions returned');
      testCase.verifyTrue(strcmp({sess.subject},'flowers'), 'Failed to filter by subject')
      
      % Test eid search
      [sess, eid] = ai.getSessions(testCase.eids);
      testCase.verifyEqual(numel(sess), 2, 'Incorrect number of sessions returned');
      testCase.verifyEqual(eid, testCase.eids, 'Inconsistent eids')
      
      % Test lab search
      sess = ai.getSessions('lab', 'cortexlab');
      testCase.verifyTrue(all(strcmp({sess.lab},'cortexlab')), 'Failed to filter by lab')
      
      % Test user search
      sess = ai.getSessions('user', 'olivier');
      correct = cellfun(@(usr)any(strcmp(usr,'olivier')), {sess.users});
      testCase.verifyTrue(all(correct), 'Failed to filter by users')
      
      % Test dataset search
      sess = ai.getSessions('data', {'clusters.probes', 'eye.blink'});
      correct = cellfun(...
        @(s)any(strcmp({s.dataset_type},'clusters.probes')) && ...
        any(strcmp({s.dataset_type},'eye.blink')), ...
        {sess.data_dataset_session_related});
      testCase.verifyTrue(all(correct), 'Failed to filter by dataset_type')
      
      % Test eid and search combo
      [sess, eid] = ai.getSessions(testCase.eids{1}, ...
        'lab', 'zadorlab', 'end_date', '2018-07-13');
      testCase.verifyEqual(numel(sess), 2, 'Incorrect number of sessions returned');
      testCase.verifyEqual(eid, testCase.eids, 'Inconsistent eids')

      % Test date_range search
      testRange = datenum([2019 1 1 ; 2019 5 31]);
      sess = ai.getSessions('date_range', testRange);
      dates = ai.datenum({sess.start_time});
      testCase.verifyTrue(all(dates > testRange(1) & dates < testRange(2)), ...
        'Failed to filter by date_range')
      
      % Test number search
      sess = ai.getSessions('number', 2);
      testCase.verifyTrue(all([sess.number]==2), 'Failed to filter by number')
      
      % Test expRef search
      refs = dat.constructExpRef({'clns0730','flowers'}, {'2018-08-24','2018-07-13'}, {1,1});
      [sess, eid] = ai.getSessions(refs);
      testCase.verifyEqual(numel(sess), 2, 'Incorrect number of sessions returned');
      testCase.verifyEqual(eid, testCase.eids, 'Inconsistent eids')
      
      % Test start_date search
      testDate = datenum('2018-07-13');
      sess = ai.getSessions('start_date', testDate);
      correct = floor(ai.datenum({sess.start_time})) == testDate;
      testCase.verifyTrue(all(correct), 'Failed to filter by start_date')
      
      % Test end_date search
      testDate = datenum('2018-07-13');
      sess = ai.getSessions('end_date', testDate);
      testCase.assertTrue(~any(emptyElems({sess.end_time})), 'Failed to filter by end_date')
      correct = floor(ai.datenum({sess.end_time})) == testDate;
      testCase.verifyTrue(all(correct), 'Failed to filter by end_date')
      
      % Test starts_before search
      testDate = datenum('2019-01-01');
      sess = ai.getSessions('starts_before', testDate);
      correct = ai.datenum({sess.start_time}) < testDate;
      testCase.verifyTrue(all(correct), 'Failed to filter by starts_before')
      
      % Test ends_before search
      testDate = datenum('2018-07-13');
      sess = ai.getSessions('ends_before', testDate);
      testCase.assertTrue(~any(emptyElems({sess.end_time})), 'Failed to filter by ends_before')
      correct = ai.datenum({sess.end_time}) < testDate;
      testCase.verifyTrue(all(correct), 'Failed to filter by ends_before')
      
      % Test starts_after search
      testDate = datenum('2019-01-01');
      sess = ai.getSessions('starts_after', testDate);
      correct = ai.datenum({sess.start_time}) > testDate;
      testCase.verifyTrue(all(correct), 'Failed to filter by starts_after')
      
      % Test ends_after search
      testDate = datenum('2018-07-13');
      sess = ai.getSessions('ends_after', testDate);
      testCase.assertTrue(~any(emptyElems({sess.end_time})), 'Failed to filter by ends_after')
      correct = ai.datenum({sess.end_time}) > testDate;
      testCase.verifyTrue(all(correct), 'Failed to filter by ends_after')
    end
    
    function test_postWater(testCase)
      % Test post while logged in
      ai = testCase.alyx;
      subject = testCase.subjects{randi(length(testCase.subjects))};
      waterPost = @()ai.postWater(subject, pi, 7.3740e+05);
      
      wa = assertWarningFree(testCase, waterPost,'Alyx:flushQueue:NotConnected');
      % Check water record
      expectedFields = {'date_time', 'water_type', 'subject', 'water_administered'};
      testCase.assertTrue(all(ismember(expectedFields,fieldnames(wa))), 'Field names missing')
      testCase.verifyEqual(wa.date_time, '2018-12-06T00:00:00', 'date_time incorrect')
      testCase.verifyEqual(wa.water_type, 'Water', 'water_type incorrect')
      testCase.verifyEqual(wa.subject, subject, 'subject incorrect')
      testCase.verifyTrue(wa.water_administered == 3.142, 'Unexpected water volume');
      % Check queue flushed
      savedPost = dir([ai.QueueDir filesep '*.post']);
      testCase.verifyEmpty(savedPost, 'Post not deleted on success')
      
      % Check invalid volume error
      testCase.verifyError(@()ai.postWater(subject, 0), 'Alyx:PostWeight:InvalidAmount');
      
      % Check session water post
      url = testCase.eids{2};
      wa = verifyWarningFree(testCase, @()ai.postWater('flowers', 2, now, 'Water', url),...
        'Failed to post water with session');
      testCase.verifyEqual(url, wa.session, 'Session mismatch');
      
      % Test behaviour when logged out
      % When headless or not connected, should save post as JSON and
      % issue warning
      ai = ai.logout;
      waterPost = @()ai.postWater(subject, pi, 7.3740e+05, 'Hydrogel');
      verifyWarning(testCase, waterPost, 'Alyx:flushQueue:NotConnected');
      % Check post was saved
      savedPost = dir([ai.QueueDir filesep '*.post']);
      testCase.assertNotEmpty(savedPost, 'Post not saved')
      fn = @()Alyx_test.loadPost(fullfile(savedPost(1).folder, savedPost(1).name));
      [jsonData, endpnt] = testCase.fatalAssertWarningFree(fn);
      testCase.verifyMatches(endpnt, 'water-administrations', 'Incorrect endpoint')
      expected = ['{"date_time":"2018-12-06T00:00:00","water_type":"Hydrogel","subject":"'...
        subject '","water_administered":3.142}'];
      testCase.verifyMatches(jsonData, expected, 'JSON data incorrect')
    end
    
    function test_getFile(testCase)
      %TODO Add test for getFile method
    end
    
    function test_postWeight(testCase)
      % Test post while logged in
      ai = testCase.alyx;
      subject = testCase.subjects{randi(length(testCase.subjects))};
      weightPost = @()ai.postWeight(25.1, subject, 7.3740e+05);
      
      wa = assertWarningFree(testCase, weightPost,'Alyx:flushQueue:NotConnected');
      % Check water record
      expectedFields = {'date_time', 'weight', 'subject', 'user', 'url'};
      testCase.assertTrue(all(ismember(expectedFields,fieldnames(wa))), 'Field names missing')
      testCase.verifyEqual(wa.date_time, '2018-12-06T00:00:00', 'date_time incorrect')
      testCase.verifyEqual(wa.weight, 25.1, 'weight incorrect')
      testCase.verifyEqual(wa.subject, subject, 'subject incorrect')
      testCase.verifyEqual(wa.user, ai.User, 'Unexpected water volume');
      % Check queue flushed
      savedPost = dir([ai.QueueDir filesep '*.post']);
      testCase.verifyEmpty(savedPost, 'Post not deleted on success')
      
      % Check invalid volume error
      testCase.verifyError(@()ai.postWeight(0, subject), 'Alyx:PostWeight:InvalidWeight');
      
      % Test behaviour when logged out
      % When headless or not connected, should save post as JSON and
      % issue warning
      ai = ai.logout;
      weightPost = @()ai.postWeight(25.1, subject, 7.3740e+05);
      verifyWarning(testCase, weightPost, 'Alyx:flushQueue:NotConnected');
      % Check post was saved
      savedPost = dir([ai.QueueDir filesep '*.post']);
      testCase.assertNotEmpty(savedPost, 'Post not saved')
      fn = @()Alyx_test.loadPost(fullfile(savedPost(1).folder, savedPost(1).name));
      [jsonData, endpnt] = testCase.fatalAssertWarningFree(fn);
      testCase.verifyEqual(endpnt, 'weighings/', 'Incorrect endpoint')
      expected = ['{"date_time":"2018-12-06T00:00:00","subject":"' ...
        subject '","weight":25.1}'];
      testCase.verifyMatches(jsonData, expected, 'JSON data incorrect')
    end
    
    function test_newExp(testCase)
      ai = testCase.alyx(1);
      subject = testCase.subjects{end};
      newExp_fn = @()newExp(ai, subject);
      wrnID = 'Alyx:registerFile:InvalidRepoPath';
      [ref1, seq, url] = testCase.verifyWarning(newExp_fn, wrnID);
      ref2 = strjoin({datestr(now, 'yyyy-mm-dd'),'1',subject},'_');
      testCase.verifyEqual(ref1, ref2, 'Experiment reference mismatch');
      testCase.verifyEqual(seq, 1, 'Experiment sequence mismatch');
      testCase.verifyMatches(url, [ai.BaseURL '/sessions'],  'Incorrect URL');
      paramsSaved = exist(dat.expFilePath(ref1, 'parameters', 'master'), 'file');
      testCase.verifyTrue(paramsSaved == 2)
      
      [ref1, seq, url] = testCase.verifyWarning(newExp_fn, wrnID);
      ref2 = strjoin({datestr(now, 'yyyy-mm-dd'),'2',subject},'_');
      testCase.verifyEqual(ref1, ref2, 'Experiment reference mismatch');
      testCase.verifyEqual(seq, 2, 'Experiment sequence mismatch');
      testCase.verifyMatches(url, [ai.BaseURL '/sessions'], 'Incorrect URL');
      
      % TODO test newExp when headless
    end
    
    function test_patch(testCase)
      % Test PATCH method for sessions endpoint
      ai = testCase.alyx(1);
      url = ['sessions/' testCase.eids{1}];
      d = struct(...
        'end_time', ai.datestr(now),...
        'n_trials', randi(1000),...
        'n_correct_trials', randi(1000));
      [d2, status] = testCase.verifyWarningFree(@()ai.postData(url, d, 'patch'));
      testCase.verifyEqual(status, 201, 'end_time not set');
      testCase.verifyEqual(d.end_time, d2.end_time, 'end_time not set');
      testCase.verifyEqual(d.n_trials, d2.n_trials, 'n_trials not set');
      testCase.verifyEqual(d.n_correct_trials, d2.n_correct_trials, ...
        'n_correct_trials not set');
      % Test behaviour when not connected
      ai = ai.logout;
      [~, status] = testCase.verifyWarning(@()ai.postData(url, d, 'patch'), ...
        'Alyx:flushQueue:NotConnected');
      testCase.verifyEqual(status, 000, 'Unexpected status code');
    end
    
    function test_updateNarrative(testCase)
      ai = testCase.alyx(1);
      url = ['sessions/' testCase.eids{1}];
      comments = '   this is \r a test\n comment\t...';
      data = testCase.verifyWarningFree(@()ai.updateNarrative(comments, url));
      testCase.verifyEqual(data, ['this is \r a test' newline ' comment\t...'])
    end
    
    function test_save_loadobj(testCase)
      ai = testCase.alyx(1);
      s = saveobj(ai);
      % Test options were removed
      testCase.verifyEmpty(s.WebOptions, 'WebOptions not removed');
      % Test presence of token, etc.
      testCase.verifyTrue(~isempty(s.Token), 'Token unset');
      % Load into new instance
      ai2 = Alyx.loadobj(s);
      testCase.verifyTrue(ai2.IsLoggedIn, 'Token and/or user no longer set')
    end
    
    function test_registerFile(testCase)
      %TODO Write test for file registration
    end
    
    function test_datestr_datenum(testCase)
      % Test datenum and datestr methods
      testDate = 7.3710e+05;
      dateStr = Alyx.datestr(7.3710e+05);
      testCase.verifyEqual(dateStr, '2018-02-09T00:00:00');
      testCase.verifyEqual(Alyx.datenum('2018-02-09T00:00:00'), testDate)
    end
    
    function test_parseAlyxInstance(testCase)
      ref = '2019-01-01_1_fake';
      ai = testCase.alyx(1);
      json = testCase.assertWarningFree(@()Alyx.parseAlyxInstance(ref, ai));
      
      [ref2, ai2] = testCase.assertWarningFree(@()Alyx.parseAlyxInstance(json));
      testCase.verifyEqual(ref, ref2, 'expRef strings don''t match')
      testCase.verifyTrue(isequal(ai, ai2), 'Instance mismatch')
    end
  end
  
  methods (Static)
    function [jsonData, endpnt] = loadPost(filepath)
      try
        % Attempt to load record
        fid = fopen(filepath);
        % First line is the endpoint
        endpnt = fgetl(fid);
        % Rest of the text is the JSON data
        jsonData = fscanf(fid,'%c');
        fclose(fid);
      catch ex
        warning(ex.identifier, '%s', ex.message)
      end
    end
    
    function resetQueue(alyxQ)
      % Create test directory if it doesn't exist
      if exist(alyxQ, 'dir') ~= 7
        mkdir(alyxQ);
      else % Delete any queued posts
        files = dir(alyxQ);
        files = {files(endsWith({files.name},{'put', 'patch', 'post'})).name};
        cellfun(@delete, fullfile(alyxQ, files))
      end
    end
  end
  
end