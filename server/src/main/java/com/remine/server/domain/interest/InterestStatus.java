package com.remine.server.domain.interest;

/** 관심사 상태(선언 순서 = 목록 순서). 마지막 캡처가 remine.interest.recent-days 이내면 RECENT, 넘으면 FORGOTTEN. */
public enum InterestStatus { FORGOTTEN, RECENT }
